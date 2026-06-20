# AI Buddies — Claude Code & Codex 实时用量监控 App 方案设计

> 目标：在 Mac 和 iOS 上实时了解我使用 Claude Code 与 Codex 的用量与明细，并给出"既不浪费、也不过度"的使用建议。
> 文档状态：v2（已做竞品核实 + 已交付可运行的核心层）。日期：2026-06-19。

---

## 0. v2 更新：竞品现状与关键决策

做之前先核实了一遍市场，结论要诚实地写在最前面：

**“看用量”这件事已经高度饱和。** 现成产品（很多免费）已覆盖本方案几乎所有展示功能：

- **CodexBar**（iPhone）：Claude/Codex/ChatGPT 等，额度+成本+预算，**经 iCloud 从 Mac 实时同步**——几乎就是本方案的架构。
- **CUStats Go**（iOS）：Claude+Codex，5h/7d 窗口，按模型，智能通知，三种尺寸主屏 Widget，后台刷新。
- **ClaudeMeter**（Mac 菜单栏 + 浏览器扩展）：读取与 claude.ai/settings/usage **同源的权威额度**（非估算）。
- 还有 Code Meter、Usage for Claude（锁屏 Widget + Apple Watch）、ClaudeBar（Claude+Codex+Gemini 一个菜单栏）、ccusage 等。

**关键决策（已定）：**

1. **不做 App 内账号登录。** Anthropic 已于 2026-02 **官方禁止**在任何第三方工具中使用订阅(Pro/Max) OAuth，违反会有封号风险；虽存在 `oauth/usage` 端点，但对第三方不开放。OpenAI 侧也无干净的“读订阅用量”官方第三方 API。→ **唯一合规的数据源是两个 CLI 登录后在本地写下的文件**（你照常用 CLI 登录，App 读结果）。这也意味着“登录后看得更清楚”的诉求，本地文件已经满足。
2. **差异化只押在 Tips/优化教练层。** 现成 App 强在“显示数字 + 到顶提醒”，弱在“个性化、可执行的优化建议”。这正是你反复强调的诉求，也是最没被做透的地方。
3. **按你的选择：仍自建完整 App**（掌控/学习/隐私）。本方案据此推进，但把重心从“又一个用量表盘”移到“**带教练的用量表盘**”。

**额度数据的合规获取（重要细节）：** Codex 把权威额度写进了本地文件（直接精确）；Claude 本地只有 token，官方% 在 HTTP header 拿不到 → 用“窗口内用量”做估算代理，并明确标注“估算”。

---

## 1. 目标与范围

一句话定位：**一个把 Claude Code 和 Codex 两边的本地用量数据统一起来、实时展示、并给出优化建议的个人仪表盘**。它不替代官方 `/usage`、`/status`，而是把两边数据合并、可视化、长期留存，并加一层"省钱 + 防限流"的智能提示。

确认的范围（来自你的选择）：

- 平台：**Mac + iOS 一起做**（数据都在 Mac 本地产生，iOS 通过 CloudKit 从 Mac 同步）。
- Mac 形态：**菜单栏常驻 + 独立窗口 Dashboard**，两者都要。
- 交付：**先出完整方案设计**（本文档），确认后再写代码。
- 核心指标（全部要）：
  1. 费用（$）估算
  2. 额度窗口（5 小时 + 每周）
  3. 按项目 / 模型拆分
  4. 使用建议 / Tips

非目标（v1 不做）：团队/多人聚合、计费对账、修改 CLI 本身、云端服务器（用 CloudKit 取代自建后端）。

---

## 2. 关键事实：数据从哪来（已核实）

这是整个方案能否成立的基础，已逐项核实。

### 2.1 Claude Code 的本地数据

- 位置：`~/.claude/projects/<编码后的项目路径>/<session-id>.jsonl`
  （Xcode 集成另有 `~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects/`，扫描时一并兼容。）
- 格式：JSONL，每行一个事件（`user` / `assistant` / `tool_use` / `tool_result` / `system`）。
- Token 数据在每条 `assistant` 消息的 `message.usage`：
  `input_tokens`、`output_tokens`、`cache_creation_input_tokens`、`cache_read_input_tokens`；模型在 `message.model`。
- **解析坑（重要）**：流式写入时 `input_tokens` 常是占位值 0/1，要以该消息最终的 `usage` 为准；并且要按 `message.id` + `requestId` 去重，避免重复计数（`ccusage` 就是这么做的）。

### 2.2 Codex 的本地数据

- 位置：`~/.codex/sessions/YYYY/MM/DD/rollout-<session-id>.jsonl`
- 格式：每行 `{ type, payload, timestamp }`，类型有 `session_meta` / `event_msg` / `response_item`。
- Token 数据在 `event_msg` 且 `payload.type === "token_count"`：
  `payload.info.total_token_usage`（**累计值**）+ `last_token_usage`；要用"本次累计 − 上次累计"还原每轮用量（input / cached input / output / reasoning / total）。
- **解析坑**：Codex 子代理（subagent）的 rollout 会**重放父线程的 token 历史**并重新打时间戳，直接累加会严重高估（社区出现过 91 倍膨胀）。需要识别并排除子代理重放。

### 2.3 额度 / 限流数据：一个关键的不对称

"实时额度窗口"是最难的部分，因为**文件里有 token 数，但不一定有官方的"剩余额度 %"**。两边情况不同：

| | 5 小时 / 每周 剩余额度的权威来源 | App 能否直接读到 |
|---|---|---|
| **Codex** | 写进了 rollout 文件：`rate_limits.primary / secondary`，含 `used_percent`、`window_minutes`、`resets_in_seconds` | ✅ **能**，直接读文件就有精确剩余 % |
| **Claude Code** | 只在 API 响应 **HTTP header**：`anthropic-ratelimit-unified-5h-utilization`、`-7d-utilization`（0.0–1.0），还有第三个 `7d_sonnet` 窗口；本地文件只有 token 数 | ⚠️ **不能直接读**，需要"估算"或后续抓 header |

结论（直接影响设计）：

- **Codex 额度窗口**：直接读文件里的 `rate_limits`，做到**精确**。
- **Claude 额度窗口**：v1 用 JSONL 时间戳 + token 重建 5h / 7d 滚动窗口，作为**估算代理值**（界面明确标注"估算"），把"抓 header 拿权威值"列入路线图。

### 2.4 官方限流规则（2026-06，已核实）

- **Claude Code**：5 小时滚动窗口 + 每周（7d）封顶，外加第三个重叠约束（`7d_sonnet`）。
  5 小时上限在 2026-05-06 翻倍；每周上限 2026-05-13 上调 50%（**2026-07-13 到期**，除非延期）。
  套餐：Pro（约 $20/月）、Max 5x（$100）、Max 20x（$200）。
- **Codex**：5 小时 + 每周双窗口**同时生效**；即使 5 小时还有余量，每周耗尽也会被挡。套餐：Plus、Pro。

> 含义：对订阅用户，真正卡住你的是**额度窗口**，不是钱；所以"额度窗口"是防过度的核心，"费用($)"更多是衡量"这订阅值不值"的价值指标。

### 2.5 计价（用于"等效费用"估算，2026-06）

订阅用户不是按 token 计费，所以"费用($)"= **等效按量付费成本**（pay-as-you-go equivalent）——用来回答"我这周相当于花了多少 API 钱 / 订阅赚没赚回来"。

每百万 token（标准价）：

| 模型 | 输入 | 输出 | 缓存读取(≈0.1×输入) |
|---|---|---|---|
| Claude Opus 4.8 | $5 | $25 | $0.50 |
| Claude Sonnet 4.6 | $3 | $15 | $0.30 |
| Claude Haiku 4.5 | $1 | $5 | $0.10 |
| Codex / GPT-5 系列 | 从维护表取 | 从维护表取 | — |

缓存写入约为输入价的 1.25×（5 分钟）/ 2×（1 小时）。**价格会变**，所以设计上不硬编码，从可维护的价格表（如 LiteLLM `model_prices` JSON）定期更新，Codex 模型价同理。

---

## 3. 整体架构

核心思路：**一份共享 Swift 核心库**做所有解析/计算，Mac 和 iOS 都复用；Mac 负责读本地文件并把**聚合结果**（不是原始 JSONL）推到 CloudKit，iOS 只读聚合。

```
┌──────────────────────── Mac ────────────────────────┐
│  ~/.claude/projects/*.jsonl    ~/.codex/sessions/*.jsonl
│            │                          │
│            ▼  (FSEvents 实时监听文件变化)
│   ┌─────────────────────────────────────────┐
│   │  UsageCore  (共享 Swift Package)          │
│   │  • Claude 解析器 / Codex 解析器           │
│   │  • 统一数据模型 (UsageEvent/Rollup)       │
│   │  • 成本引擎 (token×价格)                   │
│   │  • 窗口引擎 (5h / 7d 滚动)                 │
│   │  • Tips 引擎 (规则)                        │
│   └─────────────────────────────────────────┘
│            │                          │
│            ▼                          ▼
│   菜单栏 MenuBarExtra        窗口 Dashboard (Swift Charts)
│            │
│            ▼  写入聚合 (DailyRollup / WindowState / Tip)
│   ┌─────────────────────────────────────────┐
│   │        CloudKit 私有数据库 (iCloud)       │
│   └─────────────────────────────────────────┘
└───────────────────────────│──────────────────────────┘
                            ▼  (读取 + 推送通知)
        ┌──────────── iPhone / iPad ────────────┐
        │  iOS App (SwiftUI) + 主屏 Widget       │
        │  复用 UsageCore 的模型与 Tips           │
        └────────────────────────────────────────┘
```

为什么同步"聚合"而非原始文件：原始 JSONL 可能很大且含代码内容（隐私），CloudKit 免费额度也有限。只同步每日汇总、窗口状态、Tips 这些小记录，省流量、保隐私、够用。

---

## 4. 数据解析层（UsageCore）

统一数据模型（示意）：

```swift
enum Provider { case claude, codex }

struct UsageEvent {            // 归一化后的单次调用
    let provider: Provider
    let timestamp: Date
    let project: String        // 项目目录名
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int
    let cacheReadTokens: Int
    let sessionId: String
}

struct WindowState {           // 某个限流窗口的状态
    let provider: Provider
    let kind: WindowKind       // .fiveHour / .weekly / .weeklySonnet
    let usedPercent: Double?   // Codex=权威; Claude=估算(可空标注)
    let resetsAt: Date?
    let isEstimated: Bool
}
```

- **Claude 解析器**：遍历 JSONL → 取 `assistant.message.usage` → 按 `id`+`requestId` 去重 → 映射模型与项目（从路径解码）→ 产出 `UsageEvent`。
- **Codex 解析器**：遍历 rollout → `token_count` 差分还原每轮 → 读 `rate_limits` 生成权威 `WindowState` → **过滤子代理重放**。
- **增量解析**：记录每个文件已读到的偏移量/行数，FSEvents 触发后只读新增部分，做到"准实时"且低开销。

---

## 5. 四大核心指标的实现

### 5.1 费用（$）估算
对每个 `UsageEvent` 用价格表算等效成本（区分输入/输出/缓存读/缓存写），可按**天 / 会话 / 项目 / 模型**聚合。顶部给一句价值判断：本周 ≈ $X 等效用量，套餐 $Y → **约 Z 倍价值**。

### 5.2 额度窗口（5 小时 + 每周）
- Codex：直接用文件里的 `rate_limits`，显示**精确**剩余 %、窗口时长、重置倒计时。
- Claude：用 JSONL 重建 5h / 7d 滚动窗口的 token 用量，显示**估算**进度条（明确标"估算"），并显示距下次重置的倒计时。
- 两个 provider 各画 5h / 每周两个进度环，超阈值变色（见 Tips）。

### 5.3 按项目 / 模型拆分
对时间区间内的事件按 `project`、`model` 分组，给出 token、等效 $、占比；用条形/树状图定位"谁最耗"。

### 5.4 使用建议 / Tips
见第 6 节。

---

## 6. Tips 引擎（防浪费 + 防过度）

规则化（数据驱动），分三类。每条规则 = 触发条件 → 提示文案。

**A. 防过度 / 防限流（额度安全）**

| 触发 | 提示 |
|---|---|
| 5 小时窗口 > 80% | 「5 小时额度快到顶，先合并/暂缓重任务，约 N 分钟后重置」 |
| 周中已用 > 75% 每周额度 | 「按当前速度可能周X耗尽每周额度，建议放慢或留给关键任务」 |
| 按速率预测会提前触顶 | 显示「预计 <日期> 触顶」的 ETA |

**B. 防浪费 / 省钱（效率）**

| 触发 | 提示 |
|---|---|
| 缓存读取占比低 | 「缓存命中率低，固定 CLAUDE.md / 复用上下文可省大量输入成本」 |
| 小改动却用 Opus | 「这类小任务用 Sonnet/Haiku 成本可降 ~5×」 |
| 单会话过长无 `/clear` | 「上下文膨胀，长会话建议适时 `/clear` 重置」 |
| `cache_creation` 反复升高 | 「疑似 CLAUDE.md 被反复重读（已知问题），检查项目配置」 |

**C. 价值 / 防闲置**

| 触发 | 提示 |
|---|---|
| 本周等效 $ 远超套餐价 | 「本周已跑出约 Z 倍订阅价值」 |
| 每周额度仅用 < 25% | 「额度用得很少，可放心多用，别浪费产能」 |

规则表做成可配置（阈值、开关），后续好加新规则。

---

## 7. 同步架构（Mac → iOS）

- **CloudKit 私有数据库**（绑定你的 iCloud 账号，免费额度对这点数据绰绰有余）。
- Mac 端解析后写三类小记录：`DailyRollup`（按天×provider×项目×模型的汇总）、`WindowState`（当前 5h/周状态）、`Tip`（当前提示）。
- iOS 端订阅推送（CKSubscription）或打开即拉取；Widget 走 WidgetKit 时间线定时刷新。
- 隐私：只传数字与项目名，不传代码/对话内容；项目名是否脱敏可设开关。
- 备选（如不想用 CloudKit）：iCloud Drive 共享一个聚合 JSON 文件，或自建极简端点。**推荐 CloudKit**，最 Apple 原生、零运维。

---

## 8. UI 设计

**Mac 菜单栏（MenuBarExtra，常驻）**
- 标题栏直接显示最紧的一个数：如 `5h 96% · 周 78%` 或今日等效 `$`。
- 下拉：Claude / Codex 各一组 5h + 每周环 + 今日等效 $ + 最重要的 1 条 Tip + "打开 Dashboard"。

**Mac 窗口 Dashboard（Swift Charts）**
- 顶部：四个 KPI（本周等效 $、5h 剩余、每周剩余、价值倍数）。
- 趋势：每日 token/$ 折线；模型占比；项目 Top N 条形。
- 明细表：可按时间/项目/模型筛选排序。
- Tips 面板：全部建议 + 阈值设置。

**iOS App + 主屏 Widget**
- App：与 Dashboard 同结构的精简版（KPI + 趋势 + Tips）。
- Widget（小/中尺寸）：5h、每周两个环 + 今日等效 $，一眼看额度——这就是"随时掌握"的核心入口。
- 可选：临近限流时本地通知 / Live Activity 倒计时。

---

## 9. 技术栈与权限注意点

- 语言/框架：Swift + SwiftUI；图表用 Swift Charts；Mac 菜单栏用 `MenuBarExtra`（macOS 13+）；Widget 用 WidgetKit。
- 共享层：`UsageCore` Swift Package（模型/解析/成本/窗口/Tips），Mac 与 iOS 共用。
- 文件监听：FSEvents / `DispatchSource` 监听 `~/.claude`、`~/.codex` 实现准实时。
- **App Sandbox（关键）**：沙盒默认**读不到** `~/.claude`、`~/.codex`。三选一：
  1. 个人使用、不上架 → 关闭沙盒，直接读（最简单）；
  2. 上架 → 用安全作用域书签让你手动授权这两个目录；
  3. 用一个非沙盒小助手进程专门读文件。
  → v1 个人用，建议方案 1。
- 分发：个人自用（开发者签名直接跑）/ 公证分发 / App Store——这点会反向影响沙盒选择，需你定（见开放问题）。

---

## 10. 分阶段路线图

| 阶段 | 内容 | 产出 |
|---|---|---|
| **P0 Spike** | UsageCore 双解析器，拿你真实文件验证（命令行打印 token/$/窗口） | 验证数据正确，能跑的小工具 |
| **P1 Mac 菜单栏** | MenuBarExtra 实时 5h/每周 + 今日 $，FSEvents | 菜单栏常驻可用 |
| **P2 Mac Dashboard** | Swift Charts 历史/项目/模型 + Tips 引擎 v1 | 完整 Mac 端 |
| **P3 同步 + iOS** | CloudKit 同步 + iOS App + 主屏 Widget | iPhone 随时看 |
| **P4 打磨** | Claude 权威额度(抓 header)、限流通知、Live Activity、价格自动更新 | 体验完善 |

> 说明：你选了"先给方案设计"。如果之后愿意，P0 我可以在这个环境里先做一个**今天就能在你 Mac 上跑、直接读真实数据**的命令行/本地网页版来验证解析逻辑，再进 Swift。

---

## 11. 已知风险 / 待你拍板的开放问题

1. **Claude 额度权威值**：v1 用估算代理（够用但不等于官方 %）。要不要在 P4 投入做"抓 header 拿权威值"？
2. **分发方式**：个人自签自用 / 公证给自己装 / 上 App Store？决定沙盒与签名复杂度。
3. **套餐档位**：算剩余 % 需要知道你的 Claude（Pro/Max5x/Max20x）和 Codex（Plus/Pro）档位——手动设置即可，确认一下。
4. **Codex 价格表**：Codex/GPT-5 模型等效计价需要一份可信价格源，确认用 LiteLLM 维护表 OK 吗。
5. **隐私**：同步到 iOS 的项目名是否需要脱敏（如只留哈希/别名）？

---

## 附录 A — P0 分析器（已交付，可直接运行）

已经把整个方案最难、也最被复用的“核心层”做成了一个能在你 Mac 上直接跑的脚本：`usage_buddy.py`（纯 Python 标准库，零依赖）。它就是未来 Swift `UsageCore` 的可执行规格——解析、算钱、算窗口、出 Tips 的逻辑先在这里验证对，再翻译成 Swift。

它做了什么：扫描 `~/.claude` 与 `~/.codex` → 解析两种格式（已处理去重、累计差分、子代理重放、权威 rate_limits）→ 算 token / 等效费用 / 5h+7d 窗口 / 按项目和模型拆分 → 给出省钱·防限流·防浪费的 Tips → 写一份 `usage_snapshot.json`（结构就是未来 Mac→iOS 同步的聚合数据）。

如何运行（在你的 Mac 的“终端”里）：

```bash
cd ~/myAIBuddies            # 或这个文件所在的文件夹
python3 usage_buddy.py                 # 完整报告 + 写 JSON 快照
python3 usage_buddy.py --plan-price 200   # 传你的月付价，算“价值倍数”
python3 usage_buddy.py --days 7        # 只看最近 7 天
python3 usage_buddy.py --json          # 只输出 JSON（给程序消费）
```

已用合成数据自测通过（去重、累计、权威窗口、子代理识别、6 条 Tips 全部正确）。下一步请你在真实数据上跑一次，把输出贴回来，我据此校准字段细节，再开始写 Swift。

---

## 12. 参考来源

- Claude Code JSONL 格式：[claude-dev.tools](https://claude-dev.tools/docs/jsonl-format)、[ccusage](https://ccusage.com/guide/json-output)、[claude-usage(GitHub)](https://github.com/phuryn/claude-usage)
- Claude token 占位/去重坑：[gille.ai](https://gille.ai/en/blog/claude-code-jsonl-logs-undercount-tokens/)、[bswen](https://docs.bswen.com/blog/2026-04-01-monitor-cache-stats/)
- Codex 会话/token_count 格式：[codex-trace(GitHub)](https://github.com/PixelPaw-Labs/codex-trace)、[ccusage Codex](https://ccusage.com/guide/codex/)、[reverse engineering rollout](https://dev.to/milkoor/reverse-engineering-codex-cli-rollout-traces-3b9b)
- Codex rate_limits 字段：[openai/codex #14728](https://github.com/openai/codex/issues/14728)、[ccusage #950(子代理膨胀)](https://github.com/ryoppippi/ccusage/issues/950)
- Claude 限流 header：[anthropics/claude-code #12829](https://github.com/anthropics/claude-code/issues/12829)、[#29721](https://github.com/anthropics/claude-code/issues/29721)
- Claude 限流规则(2026)：[truefoundry](https://www.truefoundry.com/blog/claude-code-limits-explained)、[morphllm](https://www.morphllm.com/claude-code-usage-limits)、[apidog](https://apidog.com/blog/claude-code-weekly-limits-50-percent-increase-july-2026/)
- Codex 限流规则：[allthings.how](https://allthings.how/codex-token-and-rate-limits-explained-for-chatgpt-plans/)、[sessionwatcher](https://www.sessionwatcher.com/guides/how-to-check-codex-usage)
- 计价(2026)：[cloudzero](https://www.cloudzero.com/blog/claude-api-pricing/)、[metacto](https://www.metacto.com/blogs/anthropic-api-pricing-a-full-breakdown-of-costs-and-integration)
