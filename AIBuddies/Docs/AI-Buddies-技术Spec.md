# AI Buddies — 技术规格说明书（Technical Spec）

> 版本 v1 · 2026-06-19 · 供命令行模式下的编码实现
> 配套：`AI-Buddies-产品Spec.md`（产品）、`usage_buddy.py`（核心逻辑的可执行参考实现，UsageCore 直接据此移植）、`AI-Buddies-UI-原型.html`（UI 基准）

---

## 1. 架构总览

```
                 ┌──────────────────────── macOS App ────────────────────────┐
 ~/.claude ─┐    │  FileWatcher(FSEvents) → UsageCore → ViewModels             │
 ~/.codex  ─┘    │     ┌───────────── UsageCore (SPM, 跨平台) ─────────────┐   │
                 │     │ Models · ClaudeParser · CodexParser · CostEngine  │   │
                 │     │ WindowEngine · TipsEngine · Pricing · Snapshot     │   │
                 │     └────────────────────────────────────────────────────┘   │
                 │  MenuBarExtra  +  Dashboard Window (SwiftUI + Swift Charts) │
                 │            │ 写聚合                                          │
                 └────────────│──────────────────────────────────────────────┘
                              ▼
                      ┌──────────────── CloudKit 私有库 ────────────────┐
                      │  DailyRollup · WindowState · TipRecord · Settings │
                      └──────────────────────│──────────────────────────┘
                                             ▼ 读 + 推送
                 ┌──────────────────────── iOS App ──────────────────────────┐
                 │  CloudSync → UsageCore(模型/Tips 复用) → SwiftUI           │
                 │  App Group 共享 snapshot → WidgetKit(主屏/锁屏) · 通知      │
                 └─────────────────────────────────────────────────────────────┘
```

单写入者模型：只有 Mac 写 CloudKit，iOS 只读 → 无冲突合并问题。

---

## 2. 技术栈与最低版本
- Swift 5.10+，SwiftUI。
- macOS 14+（`MenuBarExtra` window style、Swift Charts 成熟）。
- iOS 17+（WidgetKit、Swift Charts、Live Activity 备选）。
- 框架：Swift Charts、WidgetKit、CloudKit、UserNotifications、CryptoKit（项目名哈希）。
- 文件监听：FSEvents（`CoreServices`）或 `DispatchSource`。
- 无第三方依赖（v1 全部用系统框架）。

---

## 3. 仓库结构

```
AIBuddies/
├─ Packages/
│  └─ UsageCore/                 # 跨平台核心逻辑（无 UI、无平台依赖）
│     ├─ Sources/UsageCore/
│     │  ├─ Models.swift
│     │  ├─ Pricing.swift
│     │  ├─ ClaudeParser.swift
│     │  ├─ CodexParser.swift
│     │  ├─ CostEngine.swift
│     │  ├─ WindowEngine.swift
│     │  ├─ TipsEngine.swift
│     │  ├─ Aggregator.swift
│     │  └─ Snapshot.swift
│     └─ Tests/UsageCoreTests/   # 用 fixture JSONL 做金标准测试
├─ Apps/
│  ├─ AIBuddiesMac/              # macOS app target
│  │  ├─ App.swift  MenuBar/  Dashboard/  FileWatcher.swift  CloudPublisher.swift  RefreshScheduler.swift
│  ├─ AIBuddiesiOS/             # iOS app target
│  │  ├─ App.swift  Screens/  CloudSubscriber.swift  Notifications.swift
│  └─ AIBuddiesWidgets/         # WidgetKit extension（iOS，可选 macOS）
├─ Shared/                       # 跨 app 共享（CloudKit schema、App Group 常量、主题）
└─ Docs/                         # 本仓库 spec 副本
```

UsageCore 是核心；两端 App 仅做平台 IO 与 UI。

---

## 4. UsageCore 设计（直接移植 `usage_buddy.py`）

### 4.1 数据模型（`Models.swift`）
```swift
public enum Provider: String, Codable { case claude, codex }
public enum WindowKind: String, Codable { case fiveHour, weekly, weeklySonnet }

public struct UsageEvent: Codable, Hashable {
    public let provider: Provider
    public let timestamp: Date?
    public let project: String
    public let model: String
    public let inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens: Int
    public let sessionId: String
}

public struct WindowState: Codable, Hashable {
    public let provider: Provider
    public let kind: WindowKind
    public let usedPercent: Double?      // Codex=权威; Claude=估算占比
    public let resetsAt: Date?
    public let isEstimated: Bool
}

public struct Tip: Codable, Hashable {
    public enum Severity: String, Codable { case danger, warn, info, success }
    public let severity: Severity
    public let category: String          // 防限流/省钱/价值/做得好…
    public let text: String
}
```

### 4.2 计价（`Pricing.swift`）
按 token 单价（USD）；以模型族匹配（含 `opus/sonnet/haiku`）。值见 `usage_buddy.py` 的 `CLAUDE_PRICES`：Opus 5/25、Sonnet 3/15、Haiku 1/5（每百万；缓存读 0.1×、缓存写 1.25×）。Codex 单价为可配置近似值。
- 价格表打包进 app，并支持从可维护源（LiteLLM `model_prices` JSON）定期刷新（P4）。
- `func cost(of event: UsageEvent) -> Double`。

### 4.3 Claude 解析（`ClaudeParser.swift`）
- 扫描 `~/.claude/projects/**/*.jsonl`（含 Xcode 集成目录）。
- 仅取 `type=="assistant"` 且存在 `message.usage`。
- **去重**：以 `(message.id, requestId)` 为 key，保留最终 usage（流式 `input_tokens` 为占位 0/1，须以最终值为准）。
- 字段：`input_tokens / output_tokens / cache_read_input_tokens / cache_creation_input_tokens`、`message.model`、`timestamp`；项目名取父目录名。
- 增量读取：记录每文件已读字节偏移，FSEvents 触发后只读新增（见 §6）。

### 4.4 Codex 解析（`CodexParser.swift`）
- 扫描 `~/.codex/sessions/**/rollout-*.jsonl`。
- 行 `{type,payload,timestamp}`；`event_msg` 且 `payload.type=="token_count"`。
- token：`info.total_token_usage` 是**累计值** → 每会话取累计最大者（或按需差分还原每轮）。字段含 `input_tokens/output_tokens/cached_input_tokens/reasoning_output_tokens/total_tokens`。
- **额度（权威）**：`payload.rate_limits.primary/secondary`（`used_percent / window_minutes / resets_in_seconds`）→ 取全局最新一条生成 `WindowState(isEstimated:false)`。
- **子代理重放**：识别"多条 token_count 集中在会话首时刻"的 rollout 并排除/标记，避免高估（参考 `usage_buddy.py` 的 `subagent_suspect` 启发式；实现时可进一步用 `session_meta` 的来源字段判定）。

### 4.5 窗口引擎（`WindowEngine.swift`）
- Codex：直接用解析得到的权威 `WindowState`。
- Claude：用最近 5h / 7d 窗口内的等效 $ 与 token 作为**估算代理**，`isEstimated:true`，并按窗口边界推算 `resetsAt`。
- 颜色阈值由 UI 层用 `usedPercent` 映射（<70 绿 /70–90 琥珀 /≥90 红）。

### 4.6 聚合（`Aggregator.swift`）
按 provider / 天 / 项目 / 模型聚合 token 与等效 $；窗口用量函数 `windowUsage(hours/days)`。对应 `usage_buddy.py` 的 `aggregate()` 与 `window_usage()`。

### 4.7 建议引擎（`TipsEngine.swift`）
实现产品 spec §7 的规则表，输入为聚合结果 + Codex 权威窗口 + 月付价，输出 `[Tip]`。逻辑以 `usage_buddy.py` 的 `build_tips()` 为准。阈值集中为可配置常量。

### 4.8 快照（`Snapshot.swift`）
产出与 `usage_buddy.py` 的 `usage_snapshot.json` 同构的 `Snapshot`（Codable）：`claude/codex` 汇总 + 窗口、`byModel`、`byProjectTop`、`byDay`、`tips`。这是 **Mac→CloudKit→iOS→Widget** 全链路传递的统一载体。

---

## 5. 数据 IO 与文件监听（Mac 专属，`FileWatcher.swift`）
- 监听目录：`~/.claude/projects`、`~/.codex/sessions`（递归）。
- 技术：FSEvents（目录级）+ 每文件读偏移缓存；debounce 合并抖动；按 RefreshScheduler 的间隔节流。
- **App Sandbox 决策**：沙盒默认读不到 `~/.claude`、`~/.codex`。
  - v1 个人自用：**关闭 App Sandbox** 直接读（最简单）。
  - 若日后上架：改用安全作用域书签让用户授权这两个目录，或拆一个非沙盒 helper。
  - 该决策写入 entitlements，并在 README 注明。

---

## 6. macOS App
- `MenuBarExtra`（`.window` 样式）承载状态项与下拉；标题用 `usedPercent` 渲染文本/颜色，可切 %/$。
- Dashboard 用普通 `Window`（`WindowGroup` / `Settings`）；`NavigationSplitView` 实现左导航 7 项；Swift Charts 画每日堆叠柱、模型/项目条形。
- 设置持久化：`UserDefaults`（套餐、月付价、菜单栏显示、刷新间隔、脱敏、外观、通知阈值）。
- `RefreshScheduler`：按间隔触发解析 + 刷新 ViewModel + 发布到 CloudKit + 评估通知。
- `CloudPublisher`：把 `Snapshot` 拆成 CloudKit 记录写入私有库（见 §8）。

---

## 7. CloudKit 同步（`Shared/CloudSchema.swift`）
- 容器：`iCloud.com.<you>.aibuddies`，**私有数据库**。
- 记录类型：
  - `DailyRollup`（recordName=`yyyy-MM-dd`）：date、claudeCost、codexCost、claudeTokens、codexTokens。
  - `WindowStateRec`（recordName=`provider#kind`）：provider、kind、usedPercent、resetsAt、isEstimated、updatedAt。
  - `TipRecord`：severity、category、text、order。
  - `SettingsRec`（单条）：套餐、月付价、阈值、脱敏开关。
- 写：Mac 端 `CKModifyRecordsOperation`，幂等 upsert（固定 recordName）。
- 读：iOS 端打开即 fetch + `CKQuerySubscription`/`CKDatabaseSubscription` 推送增量。
- 体量极小（每天数条），远低于免费额度。
- 隐私：脱敏开启时项目名以 `SHA256` 截断哈希写入。

---

## 8. iOS App + WidgetKit
- `CloudSubscriber`：拉取并缓存 `Snapshot`；写入 **App Group** 容器供 Widget 读取。
- 屏幕：首页 / 趋势 / 建议 / 设置（对应原型）。
- WidgetKit：`TimelineProvider` 从 App Group 读 `Snapshot`；
  - 小号（单端双环）、中号（两端进度条 + 今日$ + 1 条建议）、锁屏 `accessoryCircular`、Watch complication。
  - 刷新：依赖同步更新 + 系统 timeline 预算（约每 15–30 min；不追求秒级）。
- 通知：`UNUserNotificationCenter`，按 §9 阈值触发；Mac 与 iOS 各自可发，去重以"窗口+阈值+重置周期"为键。

---

## 9. 测试
- UsageCore 单元测试：放置 fixture JSONL（含流式占位重复、累计 token、`rate_limits`、子代理重放）→ 断言 token/费用/窗口/子代理识别/建议。可直接把 `usage_buddy.py` 的合成数据生成器移植为测试夹具。
- 金标准快照：对固定输入断言 `Snapshot` JSON。
- 跨端一致性：同一 `Snapshot` 在 Mac/iOS/Widget 渲染同值。

---

## 10. 里程碑（建议提交顺序）
- **M0 UsageCore**：模型 + 两解析器 + 成本/窗口/建议 + 测试通过（对照 `usage_buddy.py`）。
- **M1 Mac 菜单栏**：FileWatcher + 状态项 + 下拉 + 刷新/设置。
- **M2 Mac 仪表盘**：7 导航 + Swift Charts + 建议页 + 设置持久化 + 通知。
- **M3 同步 + iOS**：CloudKit 发布/订阅 + iOS 四屏 + App Group。
- **M4 Widget + 打磨**：主屏/锁屏 widget + 通知去重 + 价格更新 + （探索）Claude 权威额度。

---

## 11. 风险与对策
| 风险 | 对策 |
|---|---|
| 沙盒读不到 CLI 目录 | v1 关闭沙盒；上架走安全作用域书签 |
| Claude 无权威额度% | 标"估算"；P4 再评估抓 header |
| Codex 子代理重放高估 | 启发式识别 + 标记；后续用 session_meta 判定 |
| JSONL 字段跨版本变动 | 解析器容错 + 字段回退；fixture 覆盖多版本 |
| 价格变动 | 价格表可更新（LiteLLM 源） |
| Widget 刷新预算有限 | 接受分钟级；关键变化靠通知 |

---

## 12. 切到命令行前的交接清单
开 CLI 编码会话时，建议第一步：
1. `cd ~/myAIBuddies`，把本仓库的 4 个文档与 `usage_buddy.py` 作为上下文。
2. 先 `swift package init` 建 `Packages/UsageCore`，按 §4 落地模型与两解析器，把 `usage_buddy.py` 的算法逐一移植，并用 §9 的 fixture 跑通测试（M0）。
3. 用你的真实 `~/.claude`、`~/.codex` 跑一遍 `usage_buddy.py` 校准字段，再据此微调 Swift 解析器。
4. 然后建 Mac target 接 UsageCore（M1）。

> 真机数据校准是 M0 的验收前提：Swift 解析器的 token/费用应与 `usage_buddy.py` 在同一数据上的输出一致。
