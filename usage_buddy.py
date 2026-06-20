#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AI Buddies — Claude Code & Codex 用量分析器 (P0 / 核心层)

读取本机 Claude Code 和 Codex 的本地数据，计算 token / 等效费用 / 5小时+每周额度窗口 /
按项目和模型拆分，并给出"省钱 + 防限流 + 防浪费"的建议。最后写一份 JSON 快照
(usage_snapshot.json)，结构对应未来 Mac→iOS 同步用的聚合数据。

设计要点（已核实）：
  • Claude:  ~/.claude/projects/<编码路径>/<session>.jsonl, 取 assistant.message.usage,
             按 (message.id, requestId) 去重并以"最终 usage"为准（流式 input_tokens 是占位值）。
             官方剩余额度% 只在 HTTP header，本地拿不到 → 本工具用"窗口内用量"作为估算代理。
  • Codex:   ~/.codex/sessions/YYYY/MM/DD/rollout-<id>.jsonl, token_count 事件里 total_token_usage
             是累计值; rate_limits.primary/secondary 是【权威】剩余额度% + 重置倒计时，直接可读。
             子代理(subagent) rollout 会重放父历史 → 本工具按"每会话取累计最大值"并给出提示。

纯标准库，无需安装任何依赖。
用法:
  python3 usage_buddy.py                 # 扫描默认目录，打印报告 + 写 JSON 快照
  python3 usage_buddy.py --days 7        # 只统计最近 7 天
  python3 usage_buddy.py --plan-price 200  # 传入你的月付价以计算"价值倍数"
  python3 usage_buddy.py --json          # 只输出 JSON（给程序消费）
  python3 usage_buddy.py --claude-dir DIR --codex-dir DIR   # 覆盖目录（用于测试）
"""

import argparse
import json
import os
import sys
import webbrowser
import html as _html
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

# ───────────────────────────── 价格表（每 token，美元，2026-06）──────────────────────────────
# 价格会变，集中放这里方便更新。Claude 价格已核实；Codex 为近似值，请按需修正。
CLAUDE_PRICES = {
    # family:        input,   output,  cache_read, cache_write(5m≈1.25×input)
    "opus":   {"in": 5e-6,  "out": 25e-6, "cr": 0.5e-6,  "cw": 6.25e-6},
    "sonnet": {"in": 3e-6,  "out": 15e-6, "cr": 0.3e-6,  "cw": 3.75e-6},
    "haiku":  {"in": 1e-6,  "out": 5e-6,  "cr": 0.1e-6,  "cw": 1.25e-6},
}
CLAUDE_DEFAULT_FAMILY = "sonnet"

# Codex / GPT-5 系列价格未官方核实 —— 这里是占位近似值，请自行修正。Codex 的真正强项是权威额度窗口。
CODEX_PRICES = {
    "default": {"in": 1.25e-6, "out": 10e-6, "cr": 0.125e-6, "cw": 1.25e-6},
}
CODEX_PRICE_IS_APPROX = True

# ───────────────────────────── 工具函数 ──────────────────────────────

def claude_family(model: str) -> str:
    m = (model or "").lower()
    if "opus" in m:
        return "opus"
    if "sonnet" in m:
        return "sonnet"
    if "haiku" in m:
        return "haiku"
    return CLAUDE_DEFAULT_FAMILY


def parse_ts(value):
    """把各种时间戳形态解析成带时区的 datetime；失败返回 None。"""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        # 可能是秒或毫秒
        v = float(value)
        if v > 1e12:
            v /= 1000.0
        try:
            return datetime.fromtimestamp(v, tz=timezone.utc)
        except Exception:
            return None
    if isinstance(value, str):
        s = value.strip().replace("Z", "+00:00")
        try:
            d = datetime.fromisoformat(s)
            if d.tzinfo is None:
                d = d.replace(tzinfo=timezone.utc)
            return d
        except Exception:
            return None
    return None


def cost_of(tokens: dict, price: dict) -> float:
    return (
        tokens.get("in", 0) * price["in"]
        + tokens.get("out", 0) * price["out"]
        + tokens.get("cr", 0) * price["cr"]
        + tokens.get("cw", 0) * price["cw"]
    )


def fmt_usd(x: float) -> str:
    return f"${x:,.2f}"


def fmt_int(x: int) -> str:
    return f"{x:,}"


def _reset_secs(d):
    """从窗口字典里尽量取出"距重置秒数"，兼容多种字段命名。"""
    if not isinstance(d, dict):
        return None
    for k in ("resets_in_seconds", "reset_in_seconds", "seconds_until_reset", "reset_after_seconds"):
        if d.get(k) is not None:
            return d[k]
    for k in ("resets_at", "reset_at", "resets"):
        v = parse_ts(d.get(k))
        if v:
            return max(0, (v - datetime.now(timezone.utc)).total_seconds())
    return None


def human_duration(seconds):
    if seconds is None:
        return "?"
    seconds = int(seconds)
    if seconds <= 0:
        return "现在"
    h, rem = divmod(seconds, 3600)
    m, _ = divmod(rem, 60)
    if h:
        return f"{h}小时{m}分"
    return f"{m}分"


# ───────────────────────────── Claude 解析 ──────────────────────────────

def scan_claude(dirs, since_dt):
    """返回 (events, files_seen)。events: 每条去重后的 assistant 调用。"""
    dedup = {}  # key=(id, requestId) -> record（保留最终 usage）
    files_seen = 0
    for base in dirs:
        base = Path(base).expanduser()
        if not base.exists():
            continue
        for fp in base.rglob("*.jsonl"):
            files_seen += 1
            project = fp.parent.name
            try:
                with open(fp, "r", encoding="utf-8", errors="ignore") as fh:
                    for line in fh:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            obj = json.loads(line)
                        except Exception:
                            continue
                        if obj.get("type") != "assistant":
                            continue
                        msg = obj.get("message", {}) or {}
                        usage = msg.get("usage") or obj.get("usage")
                        if not usage:
                            continue
                        ts = parse_ts(obj.get("timestamp") or msg.get("timestamp"))
                        mid = msg.get("id") or obj.get("uuid") or obj.get("id")
                        rid = obj.get("requestId") or obj.get("request_id") or ""
                        key = (mid, rid) if mid else (id(obj), rid)
                        dedup[key] = {
                            "ts": ts,
                            "project": project,
                            "model": msg.get("model") or "unknown",
                            "in": int(usage.get("input_tokens", 0) or 0),
                            "out": int(usage.get("output_tokens", 0) or 0),
                            "cr": int(usage.get("cache_read_input_tokens", 0) or 0),
                            "cw": int(usage.get("cache_creation_input_tokens", 0) or 0),
                        }
            except Exception:
                continue

    events = []
    for rec in dedup.values():
        if since_dt and rec["ts"] and rec["ts"] < since_dt:
            continue
        events.append(rec)
    return events, files_seen


# ───────────────────────────── Codex 解析 ──────────────────────────────

def scan_codex(codex_dir, since_dt):
    """返回 (events, latest_rate_limits, files_seen, subagent_suspect)。

    token 总量按"每会话取累计最大值"汇总（total_token_usage 是累计值），
    rate_limits 取全局最新一条（权威额度）。
    """
    base = Path(codex_dir).expanduser()
    files_seen = 0
    per_session = {}  # session_id -> {tokens..., ts, model}
    latest_rl = None  # (ts, rate_limits)
    subagent_suspect = 0

    if not base.exists():
        return [], None, 0, 0

    for fp in base.rglob("rollout-*.jsonl"):
        files_seen += 1
        sid = fp.stem  # rollout-<id>
        model = "unknown"
        best = None  # 该会话累计最大的一条 total_token_usage
        first_tc_ts = None
        tc_count = 0
        try:
            with open(fp, "r", encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    typ = obj.get("type")
                    payload = obj.get("payload", {}) or {}
                    ts = parse_ts(obj.get("timestamp") or payload.get("timestamp"))

                    if model == "unknown":
                        _m = (payload.get("model") or obj.get("model")
                              or (payload.get("info") or {}).get("model")
                              or (payload.get("turn_context") or {}).get("model"))
                        if _m:
                            model = _m

                    if typ == "session_meta":
                        nested = payload.get("payload") if isinstance(payload.get("payload"), dict) else {}
                        model = (payload.get("model") or payload.get("model_slug")
                                 or nested.get("model") or model)

                    if typ == "event_msg" and payload.get("type") == "token_count":
                        tc_count += 1
                        if first_tc_ts is None:
                            first_tc_ts = ts
                        info = payload.get("info", {}) or {}
                        total = info.get("total_token_usage", {}) or {}
                        tokens = {
                            "in": int(total.get("input_tokens", 0) or 0),
                            "out": int(total.get("output_tokens", 0) or 0),
                            "cr": int(total.get("cached_input_tokens",
                                                total.get("cache_read_input_tokens", 0)) or 0),
                            "cw": 0,
                            "reasoning": int(total.get("reasoning_output_tokens",
                                                       total.get("reasoning_tokens", 0)) or 0),
                            "total": int(total.get("total_tokens", 0) or 0),
                        }
                        # 取该会话累计最大者
                        if best is None or tokens["total"] >= best["total"]:
                            best = dict(tokens)
                            best["ts"] = ts
                        # rate_limits 取全局最新
                        rl = payload.get("rate_limits") or info.get("rate_limits")
                        if rl:
                            if latest_rl is None or (ts and latest_rl[0] and ts > latest_rl[0]):
                                latest_rl = (ts, rl)
                            elif latest_rl is None:
                                latest_rl = (ts, rl)
        except Exception:
            continue

        # 子代理嫌疑：很多 token_count 集中在同一(创建)时刻 = 父历史重放
        if tc_count >= 3 and first_tc_ts and best and best.get("ts") == first_tc_ts:
            subagent_suspect += 1

        if best:
            best["session"] = sid
            best["model"] = model
            per_session[sid] = best

    events = []
    for rec in per_session.values():
        if since_dt and rec.get("ts") and rec["ts"] < since_dt:
            continue
        events.append(rec)

    return events, latest_rl, files_seen, subagent_suspect


# ───────────────────────────── 聚合 ──────────────────────────────

def aggregate(claude_events, codex_events):
    agg = {
        "claude": {"in": 0, "out": 0, "cr": 0, "cw": 0, "cost": 0.0, "calls": 0},
        "codex": {"in": 0, "out": 0, "cr": 0, "cost": 0.0, "sessions": 0},
        "by_project": defaultdict(lambda: {"tokens": 0, "cost": 0.0, "provider": ""}),
        "by_model": defaultdict(lambda: {"tokens": 0, "cost": 0.0}),
        "by_day": defaultdict(lambda: {"cost": 0.0, "tokens": 0}),
    }

    for e in claude_events:
        fam = claude_family(e["model"])
        price = CLAUDE_PRICES[fam]
        c = cost_of(e, price)
        tok = e["in"] + e["out"] + e["cr"] + e["cw"]
        agg["claude"]["in"] += e["in"]; agg["claude"]["out"] += e["out"]
        agg["claude"]["cr"] += e["cr"]; agg["claude"]["cw"] += e["cw"]
        agg["claude"]["cost"] += c; agg["claude"]["calls"] += 1
        agg["by_project"][f"[C] {e['project']}"]["tokens"] += tok
        agg["by_project"][f"[C] {e['project']}"]["cost"] += c
        agg["by_project"][f"[C] {e['project']}"]["provider"] = "claude"
        agg["by_model"][f"claude/{fam}"]["tokens"] += tok
        agg["by_model"][f"claude/{fam}"]["cost"] += c
        if e["ts"]:
            day = e["ts"].astimezone().strftime("%Y-%m-%d")
            agg["by_day"][day]["cost"] += c; agg["by_day"][day]["tokens"] += tok

    price = CODEX_PRICES["default"]
    for e in codex_events:
        c = cost_of(e, price)
        tok = e.get("total") or (e["in"] + e["out"] + e["cr"])
        agg["codex"]["in"] += e["in"]; agg["codex"]["out"] += e["out"]
        agg["codex"]["cr"] += e["cr"]; agg["codex"]["cost"] += c
        agg["codex"]["sessions"] += 1
        agg["by_project"][f"[X] {e.get('session','?')[:18]}"]["tokens"] += tok
        agg["by_project"][f"[X] {e.get('session','?')[:18]}"]["cost"] += c
        agg["by_project"][f"[X] {e.get('session','?')[:18]}"]["provider"] = "codex"
        agg["by_model"][f"codex/{e.get('model','unknown')}"]["tokens"] += tok
        agg["by_model"][f"codex/{e.get('model','unknown')}"]["cost"] += c
        if e.get("ts"):
            day = e["ts"].astimezone().strftime("%Y-%m-%d")
            agg["by_day"][day]["cost"] += c; agg["by_day"][day]["tokens"] += tok

    return agg


def window_usage(claude_events, hours=None, days=None):
    """Claude 估算代理：统计某窗口内的等效 $ 与 token。"""
    now = datetime.now(timezone.utc)
    if hours:
        start = now - timedelta(hours=hours)
    else:
        start = now - timedelta(days=days)
    cost = 0.0
    tok = 0
    for e in claude_events:
        if not e["ts"] or e["ts"] < start:
            continue
        price = CLAUDE_PRICES[claude_family(e["model"])]
        cost += cost_of(e, price)
        tok += e["in"] + e["out"] + e["cr"] + e["cw"]
    return cost, tok


# ───────────────────────────── Tips 引擎 ──────────────────────────────

def build_tips(claude_events, codex_events, agg, codex_rl, plan_price):
    tips = []

    # A. 防限流（Codex 权威额度）
    if codex_rl:
        rl = codex_rl[1]
        prim = rl.get("primary", {}) or {}
        sec = rl.get("secondary", {}) or {}
        pu = prim.get("used_percent")
        su = sec.get("used_percent")
        if pu is not None and pu >= 80:
            tips.append(("⚠️ 防限流", f"Codex 5小时额度已用 {pu:.0f}%，约 "
                         f"{human_duration(_reset_secs(prim))}后重置，建议先合并/暂缓重任务。"))
        if su is not None and su >= 75:
            tips.append(("⚠️ 防限流", f"Codex 每周额度已用 {su:.0f}%，留点给关键任务，避免周末断档。"))
        if su is not None and su < 25:
            tips.append(("💡 防闲置", f"Codex 每周额度才用 {su:.0f}%，还有大量余量，可放心多用。"))

    # B. 防浪费（模型选择）—— Opus 用在小回复上
    opus = [e for e in claude_events if claude_family(e["model"]) == "opus"]
    opus_small = [e for e in opus if e["out"] < 400]
    if len(opus) >= 10 and len(opus_small) / max(len(opus), 1) > 0.4:
        tips.append(("💸 省钱", f"有 {len(opus_small)} 次 Opus 调用输出很短（小任务）。"
                     "这类任务换 Sonnet/Haiku，成本可降约 5×。"))

    # C. 防浪费（缓存命中）
    cl = agg["claude"]
    denom = cl["in"] + cl["cr"] + cl["cw"]
    if denom > 200_000:
        ratio = cl["cr"] / denom
        if ratio < 0.3:
            tips.append(("💸 省钱", f"Claude 缓存读取占比仅 {ratio*100:.0f}%。"
                         "固定 CLAUDE.md、复用稳定上下文可大幅省输入成本。"))
        elif ratio > 0.7:
            tips.append(("✅ 做得好", f"Claude 缓存命中率 {ratio*100:.0f}%，缓存用得不错。"))

    # D. 价值（等效 $ vs 订阅价）
    cost7, _ = window_usage(claude_events, days=7)
    if plan_price and cost7 > 0:
        monthly_est = cost7 / 7 * 30
        mult = monthly_est / plan_price
        mult_str = "<0.1×" if mult < 0.1 else f"{mult:.1f}×"
        tips.append(("📈 价值", f"近7天 Claude 等效 ≈ {fmt_usd(cost7)}（折月≈{fmt_usd(monthly_est)}），"
                     f"约为 {fmt_usd(plan_price)} 月费的 {mult_str}（仅 Claude 部分）。"))

    # E. 防过度（Claude 近5小时突增）
    cost5h, _ = window_usage(claude_events, hours=5)
    cost7d_avg5h = (cost7 / (7 * 24 / 5)) if cost7 else 0  # 平均每个5h窗的量
    if cost7d_avg5h > 0 and cost5h > 3 * cost7d_avg5h and cost5h > 1:
        tips.append(("⚠️ 防过度", f"最近5小时 Claude 用量（≈{fmt_usd(cost5h)}）明显高于你的平时节奏，"
                     "注意别在短时间内冲顶 5 小时窗口。"))

    if not tips:
        tips.append(("ℹ️", "暂无明显问题。数据越多，建议越准。"))
    return tips


# ───────────────────────────── 报告 ──────────────────────────────

def build_snapshot(agg, claude_events, codex_events, codex_rl, tips, plan_price):
    cost5h, tok5h = window_usage(claude_events, hours=5)
    cost7d, tok7d = window_usage(claude_events, days=7)
    codex_windows = None
    if codex_rl:
        rl = codex_rl[1]
        codex_windows = {
            "primary": rl.get("primary"),
            "secondary": rl.get("secondary"),
            "as_of": codex_rl[0].isoformat() if codex_rl[0] else None,
            "authoritative": True,
        }
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "claude": {
            "calls": agg["claude"]["calls"],
            "tokens": {k: agg["claude"][k] for k in ("in", "out", "cr", "cw")},
            "equiv_cost_usd": round(agg["claude"]["cost"], 4),
            "window_5h_estimate": {"equiv_cost_usd": round(cost5h, 4), "tokens": tok5h,
                                   "authoritative": False},
            "window_7d_estimate": {"equiv_cost_usd": round(cost7d, 4), "tokens": tok7d,
                                   "authoritative": False},
        },
        "codex": {
            "sessions": agg["codex"]["sessions"],
            "tokens": {k: agg["codex"][k] for k in ("in", "out", "cr")},
            "equiv_cost_usd_approx": round(agg["codex"]["cost"], 4),
            "windows": codex_windows,
        },
        "by_model": {k: {"tokens": v["tokens"], "equiv_cost_usd": round(v["cost"], 4)}
                     for k, v in sorted(agg["by_model"].items(),
                                        key=lambda kv: -kv[1]["cost"])},
        "by_project_top": [
            {"name": k, "tokens": v["tokens"], "equiv_cost_usd": round(v["cost"], 4),
             "provider": v["provider"]}
            for k, v in sorted(agg["by_project"].items(), key=lambda kv: -kv[1]["cost"])[:10]
        ],
        "by_day": {k: {"equiv_cost_usd": round(v["cost"], 4), "tokens": v["tokens"]}
                   for k, v in sorted(agg["by_day"].items())},
        "tips": [{"kind": k, "text": t} for k, t in tips],
        "plan_price_usd": plan_price,
    }


def print_report(agg, claude_events, codex_events, codex_rl, tips,
                 claude_files, codex_files, subagent_suspect, plan_price):
    line = "─" * 60
    print(line)
    print("  AI Buddies — Claude Code & Codex 用量报告")
    print(f"  生成时间 {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print(line)

    if claude_files == 0 and codex_files == 0:
        print("\n  ⚠️ 没扫描到任何数据文件。")
        print("     Claude 应在 ~/.claude/projects/，Codex 在 ~/.codex/sessions/。")
        print("     若你用的是非默认路径，可用 --claude-dir / --codex-dir 指定。\n")
        return

    cl = agg["claude"]
    print(f"\n▌Claude Code   （扫描 {claude_files} 个文件，{cl['calls']} 次调用）")
    print(f"   等效费用    {fmt_usd(cl['cost'])}   (= 按量付费的等价成本)")
    print(f"   输入        {fmt_int(cl['in'])}   输出 {fmt_int(cl['out'])}")
    print(f"   缓存读取    {fmt_int(cl['cr'])}   缓存写入 {fmt_int(cl['cw'])}")

    cost5h, tok5h = window_usage(claude_events, hours=5)
    cost7d, tok7d = window_usage(claude_events, days=7)
    print(f"   近5小时(估算)  {fmt_usd(cost5h)} / {fmt_int(tok5h)} tok")
    print(f"   近7天 (估算)   {fmt_usd(cost7d)} / {fmt_int(tok7d)} tok")
    print("   注：Claude 官方剩余额度% 仅在 HTTP header，本地拿不到，以上为用量估算代理。")

    cx = agg["codex"]
    print(f"\n▌Codex        （扫描 {codex_files} 个文件，{cx['sessions']} 个会话）")
    approx = " ≈(价格近似)" if CODEX_PRICE_IS_APPROX else ""
    print(f"   等效费用    {fmt_usd(cx['cost'])}{approx}")
    print(f"   输入 {fmt_int(cx['in'])}   输出 {fmt_int(cx['out'])}   缓存 {fmt_int(cx['cr'])}")
    if codex_rl:
        rl = codex_rl[1]
        prim = rl.get("primary", {}) or {}
        sec = rl.get("secondary", {}) or {}
        if prim.get("used_percent") is not None:
            print(f"   5小时额度(权威)  已用 {prim['used_percent']:.0f}%  "
                  f"· {human_duration(_reset_secs(prim))}后重置")
        if sec.get("used_percent") is not None:
            print(f"   每周额度(权威)   已用 {sec['used_percent']:.0f}%  "
                  f"· {human_duration(_reset_secs(sec))}后重置")
    else:
        print("   （未读到 rate_limits；可能是旧版本日志或暂无会话）")
    if subagent_suspect:
        print(f"   注：检测到 {subagent_suspect} 个疑似子代理会话（重放父历史），token 可能偏高。")

    # 模型拆分
    if agg["by_model"]:
        print("\n▌按模型（等效费用）")
        for name, v in sorted(agg["by_model"].items(), key=lambda kv: -kv[1]["cost"])[:8]:
            print(f"   {name:<22} {fmt_usd(v['cost']):>10}   {fmt_int(v['tokens'])} tok")

    # 项目拆分
    if agg["by_project"]:
        print("\n▌按项目 / 会话 Top（等效费用）")
        for name, v in sorted(agg["by_project"].items(), key=lambda kv: -kv[1]["cost"])[:8]:
            print(f"   {name:<26} {fmt_usd(v['cost']):>10}   {fmt_int(v['tokens'])} tok")

    # Tips
    print("\n▌Tips —— 省钱 / 防限流 / 防浪费")
    for kind, text in tips:
        print(f"   {kind}  {text}")
    print()


# ───────────────────────────── main ──────────────────────────────

_CSS = """
:root{--bg:#fff;--bg2:#f6f5f0;--bg3:#eceae2;--text:#201f1d;--text2:#5f5e5a;--text3:#8d8c83;--border:#e7e5dd;--border2:#d6d4ca;--info-bg:#e6f1fb;--info:#185fa5;--warn-bg:#faeeda;--warn:#854f0b;--danger-bg:#fcebeb;--danger:#a32d2d;--success-bg:#eaf3de;--success:#3b6d11;--claude:#d85a30;--codex:#0f6e56;--radius:10px}
@media(prefers-color-scheme:dark){:root{--bg:#1e1d1b;--bg2:#272623;--bg3:#302e2a;--text:#f2f1ec;--text2:#b4b2a9;--text3:#8d8c83;--border:#3a3833;--border2:#4a4843;--info-bg:#0c2236;--info:#85b7eb;--warn-bg:#3a2a0e;--warn:#fac775;--danger-bg:#3a1414;--danger:#f09595;--success-bg:#1a2a0c;--success:#c0dd97}}
*{box-sizing:border-box}body{margin:0;background:var(--bg3);color:var(--text);font:15px/1.5 -apple-system,"PingFang SC","Segoe UI",system-ui,sans-serif;padding:24px}
.wrap{max-width:920px;margin:0 auto}h1{font-size:20px;font-weight:600;margin:0 0 2px}.sub{color:var(--text3);font-size:12px;margin:0 0 18px}
.card{background:var(--bg);border:1px solid var(--border);border-radius:var(--radius);padding:14px 16px;margin-bottom:14px}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:14px}
.kpi{background:var(--bg);border:1px solid var(--border);border-radius:var(--radius);padding:11px 13px}.kpi .l{font-size:12px;color:var(--text2)}.kpi .n{font-size:22px;font-weight:600}
.row{display:flex;align-items:center;gap:10px}.muted{color:var(--text2)}
.badge{font-size:11px;padding:1px 7px;border-radius:6px;font-weight:600}
.b-danger{background:var(--danger-bg);color:var(--danger)}.b-warn{background:var(--warn-bg);color:var(--warn)}.b-info{background:var(--info-bg);color:var(--info)}.b-success{background:var(--success-bg);color:var(--success)}.b-est{background:var(--bg3);color:var(--text2)}
table{width:100%;border-collapse:collapse;font-size:13px}td{padding:6px 4px;border-bottom:1px solid var(--border)}
.track{height:7px;background:var(--bg3);border-radius:6px;overflow:hidden}.track>span{display:block;height:100%}
.tip{display:flex;gap:8px;align-items:flex-start;padding:5px 0;font-size:13px}.hint{font-size:12px;color:var(--text3)}
@media(max-width:680px){.grid{grid-template-columns:repeat(2,1fr)}}
"""


def _sev(kind):
    k = kind or ""
    if "限流" in k:
        return "danger"
    if "过度" in k or "省钱" in k:
        return "warn"
    if "价值" in k:
        return "info"
    return "success"


def _ring(pct, size=70):
    pct = int(round(max(0, min(100, pct))))
    color = "#e24b4a" if pct >= 90 else "#ba7517" if pct >= 70 else "#1d9e75"
    return ('<svg width="%d" height="%d" viewBox="0 0 36 36">'
            '<circle cx="18" cy="18" r="16" fill="none" stroke="var(--border2)" stroke-width="3.4"/>'
            '<circle cx="18" cy="18" r="16" fill="none" stroke="%s" stroke-width="3.4" stroke-linecap="round" '
            'pathLength="100" stroke-dasharray="%d 100" transform="rotate(-90 18 18)"/>'
            '<text x="18" y="20" text-anchor="middle" style="font-size:9px;font-weight:600;fill:var(--text)">%d%%</text></svg>'
            ) % (size, size, color, pct, pct)


def render_html(s):
    e = _html.escape
    cl, cx = s["claude"], s["codex"]
    cl_cost = cl.get("equiv_cost_usd", 0)
    cx_cost = cx.get("equiv_cost_usd_approx", 0)
    win = cx.get("windows") or {}
    prim = (win.get("primary") or {}) if win else {}
    sec = (win.get("secondary") or {}) if win else {}
    cx5 = (100 - prim["used_percent"]) if prim.get("used_percent") is not None else None
    cxw = (100 - sec["used_percent"]) if sec.get("used_percent") is not None else None
    w5 = cl.get("window_5h_estimate", {})
    w7 = cl.get("window_7d_estimate", {})
    p = []
    p.append("<!doctype html><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>")
    p.append("<title>AI Buddies 仪表盘</title><style>" + _CSS + "</style><div class='wrap'>")
    p.append("<h1>AI Buddies — 用量仪表盘</h1><p class='sub'>生成于 " + e(s.get("generated_at", "")) + " · 数据来自本地 ~/.claude 与 ~/.codex · 离线</p>")

    def kpi(l, n, extra=""):
        return "<div class='kpi'><div class='l'>" + l + "</div><div class='n'>" + n + "</div>" + ("<div class='hint'>" + extra + "</div>" if extra else "") + "</div>"

    p.append("<div class='grid'>")
    p.append(kpi("等效合计", "$%.2f" % (cl_cost + cx_cost), "扫描范围 · 可加 --days 7"))
    p.append(kpi("Codex 5h 剩余", ("%d%%" % cx5) if cx5 is not None else "—", "权威" if cx5 is not None else "无数据"))
    p.append(kpi("Codex 每周剩余", ("%d%%" % cxw) if cxw is not None else "—", "权威" if cxw is not None else "无数据"))
    p.append(kpi("调用 / 会话", "%d / %d" % (cl.get("calls", 0), cx.get("sessions", 0))))
    p.append("</div>")

    p.append("<div class='row' style='gap:14px;align-items:stretch;flex-wrap:wrap'>")
    p.append("<div class='card' style='flex:1;min-width:260px'><div class='row' style='margin-bottom:10px'><span style='width:8px;height:8px;border-radius:50%;background:var(--claude)'></span><b>Claude Code</b><span class='badge b-est' style='margin-left:auto'>估算</span></div>")
    p.append("<div class='muted' style='font-size:13px'>等效费用 <b style='color:var(--text)'>$%.2f</b></div>" % cl_cost)
    p.append("<div class='muted' style='font-size:13px;margin-top:6px'>近 5 小时 ≈ $%.2f · 近 7 天 ≈ $%.2f</div>" % (w5.get("equiv_cost_usd", 0), w7.get("equiv_cost_usd", 0)))
    p.append("<div class='hint' style='margin-top:8px'>官方剩余% 仅在 HTTP header，本地不可得，以上为用量估算代理。</div></div>")

    p.append("<div class='card' style='flex:1;min-width:260px'><div class='row' style='margin-bottom:10px'><span style='width:8px;height:8px;border-radius:50%;background:var(--codex)'></span><b>Codex</b><span class='badge b-success' style='margin-left:auto'>权威</span></div>")
    if prim.get("used_percent") is not None or sec.get("used_percent") is not None:
        p.append("<div class='row' style='gap:22px;justify-content:center;margin:4px 0'>")
        if prim.get("used_percent") is not None:
            p.append("<div style='text-align:center'>" + _ring(prim["used_percent"]) + "<div class='muted' style='font-size:12px'>5 小时 · " + e(human_duration(_reset_secs(prim))) + "后</div></div>")
        if sec.get("used_percent") is not None:
            p.append("<div style='text-align:center'>" + _ring(sec["used_percent"]) + "<div class='muted' style='font-size:12px'>每周 · " + e(human_duration(_reset_secs(sec))) + "后</div></div>")
        p.append("</div>")
    else:
        p.append("<div class='hint'>未读到 rate_limits（旧版日志或暂无会话）。</div>")
    p.append("<div class='muted' style='font-size:13px;margin-top:6px'>等效费用 ≈ $%.2f <span class='badge b-warn'>价格近似</span></div></div>" % cx_cost)
    p.append("</div>")

    bm = s.get("by_model", {})
    if bm:
        mx = max([v["equiv_cost_usd"] for v in bm.values()] + [0.0001])
        p.append("<div class='card'><b>按模型 · 等效费用</b><table>")
        for name, v in bm.items():
            color = "var(--claude)" if name.startswith("claude") else "var(--codex)"
            p.append("<tr><td style='width:170px' class='muted'>" + e(name) + "</td><td><div class='track'><span style='width:%d%%;background:%s'></span></div></td><td style='width:70px;text-align:right'>$%.1f</td></tr>" % (int(v["equiv_cost_usd"] / mx * 100), color, v["equiv_cost_usd"]))
        p.append("</table></div>")

    bp = s.get("by_project_top", [])
    if bp:
        mx = max([x["equiv_cost_usd"] for x in bp] + [0.0001])
        p.append("<div class='card'><b>Top 项目 / 会话</b><table>")
        for x in bp:
            p.append("<tr><td style='width:210px' class='muted'>" + e(str(x["name"])) + "</td><td><div class='track'><span style='width:%d%%;background:var(--text3)'></span></div></td><td style='width:70px;text-align:right'>$%.1f</td></tr>" % (int(x["equiv_cost_usd"] / mx * 100), x["equiv_cost_usd"]))
        p.append("</table></div>")

    tips = s.get("tips", [])
    if tips:
        p.append("<div class='card'><b>建议 · 省钱 / 防限流 / 防浪费</b>")
        for t in tips:
            p.append("<div class='tip'><span class='badge b-" + _sev(t.get("kind", "")) + "'>" + e(t.get("kind", "")) + "</span><span>" + e(t.get("text", "")) + "</span></div>")
        p.append("</div>")

    p.append("<p class='hint'>由 usage_buddy.py 生成 · 数据不出本机</p></div>")
    return "".join(p)


def main():
    ap = argparse.ArgumentParser(description="Claude Code & Codex 用量分析器")
    ap.add_argument("--days", type=int, default=None, help="只统计最近 N 天")
    ap.add_argument("--plan-price", type=float, default=None, help="你的月付价(美元)，用于价值倍数")
    ap.add_argument("--json", action="store_true", help="只输出 JSON 快照")
    ap.add_argument("--claude-dir", action="append", default=None, help="覆盖 Claude 目录（可多次）")
    ap.add_argument("--codex-dir", default=None, help="覆盖 Codex sessions 目录")
    ap.add_argument("--out", default="usage_snapshot.json", help="JSON 快照输出路径")
    ap.add_argument("--html", nargs="?", const="ai_buddies_dashboard.html", default=None,
                    help="生成 HTML 仪表盘（可指定路径，默认 ai_buddies_dashboard.html）")
    ap.add_argument("--open", action="store_true", help="生成 HTML 后在浏览器打开")
    ap.add_argument("--debug-codex", action="store_true",
                    help="打印最近一个 Codex 会话的 session_meta 与 token_count 原始结构（用于字段校准）")
    args = ap.parse_args()

    claude_dirs = args.claude_dir or [
        "~/.claude/projects",
        "~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects",
    ]
    codex_dir = args.codex_dir or "~/.codex/sessions"

    if args.debug_codex:
        base = Path(codex_dir).expanduser()
        files = sorted(base.rglob("rollout-*.jsonl"))
        if not files:
            print("未找到 Codex rollout 文件于", base)
            return
        f = files[-1]
        print("最近会话文件:", f)
        shown_meta = shown_tc = False
        for line in open(f, encoding="utf-8", errors="ignore"):
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("type") == "session_meta" and not shown_meta:
                print("\nSESSION_META:\n", json.dumps(o, ensure_ascii=False)[:700])
                shown_meta = True
            pl = o.get("payload") or {}
            if o.get("type") == "event_msg" and pl.get("type") == "token_count" and not shown_tc:
                print("\nTOKEN_COUNT:\n", json.dumps(o, ensure_ascii=False)[:900])
                shown_tc = True
            if shown_meta and shown_tc:
                break
        return

    since_dt = None
    if args.days:
        since_dt = datetime.now(timezone.utc) - timedelta(days=args.days)

    claude_events, claude_files = scan_claude(claude_dirs, since_dt)
    codex_events, codex_rl, codex_files, subagent_suspect = scan_codex(codex_dir, since_dt)

    agg = aggregate(claude_events, codex_events)
    tips = build_tips(claude_events, codex_events, agg, codex_rl, args.plan_price)
    snapshot = build_snapshot(agg, claude_events, codex_events, codex_rl, tips, args.plan_price)

    try:
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(snapshot, fh, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"(写 JSON 快照失败: {e})", file=sys.stderr)

    html_path = None
    if args.html:
        try:
            html_path = os.path.abspath(args.html)
            with open(html_path, "w", encoding="utf-8") as fh:
                fh.write(render_html(snapshot))
            if args.open:
                webbrowser.open("file://" + html_path)
        except Exception as e:
            print(f"(写 HTML 失败: {e})", file=sys.stderr)
            html_path = None

    if args.json:
        print(json.dumps(snapshot, ensure_ascii=False, indent=2))
    else:
        print_report(agg, claude_events, codex_events, codex_rl, tips,
                     claude_files, codex_files, subagent_suspect, args.plan_price)
        print(f"  JSON 快照已写入: {args.out}")
        if html_path:
            print(f"  HTML 仪表盘: {html_path}")


if __name__ == "__main__":
    main()
