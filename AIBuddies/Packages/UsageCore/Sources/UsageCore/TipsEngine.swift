import Foundation

/// Rule-based coaching engine. Ported from `usage_buddy.py` `build_tips`
/// (product spec §7). Thresholds are centralized as configurable constants.
public enum TipsEngine {

    public struct Thresholds: Sendable {
        public var codexPrimaryDanger = 80.0
        public var codexSecondaryWarn = 75.0
        public var codexSecondaryIdle = 25.0
        public var opusSmallOutputTokens = 400
        public var opusSmallShare = 0.4
        public var opusMinCalls = 10
        public var claudeCacheDenomMin = 200_000
        public var cacheLowShare = 0.3
        public var cacheGoodShare = 0.7
        public var overUseMultiple = 3.0
        public var overUseMinUSD = 1.0
        public init() {}
    }

    public static func build(
        claudeEvents: [UsageEvent],
        codexEvents: [UsageEvent],
        aggregation: Aggregation,
        codexRateLimit: DatedRateLimits?,
        planPriceUSD: Double?,
        thresholds: Thresholds = Thresholds(),
        now: Date = Date()
    ) -> [Tip] {
        var tips: [Tip] = []

        // A. Anti-throttle (Codex authoritative quota)
        if let rl = codexRateLimit?.limits {
            if let pu = rl.primary?.usedPercent, pu >= thresholds.codexPrimaryDanger {
                let reset = Formatting.humanDuration(rl.primary?.resetsInSeconds)
                tips.append(Tip(
                    severity: .danger, category: "防限流",
                    text: "Codex 5小时额度已用 \(pct(pu))%，约 \(reset)后重置，建议先合并/暂缓重任务。"
                ))
            }
            if let su = rl.secondary?.usedPercent, su >= thresholds.codexSecondaryWarn {
                tips.append(Tip(
                    severity: .warn, category: "防限流",
                    text: "Codex 每周额度已用 \(pct(su))%，留点给关键任务，避免周末断档。"
                ))
            }
            if let su = rl.secondary?.usedPercent, su < thresholds.codexSecondaryIdle {
                tips.append(Tip(
                    severity: .success, category: "防闲置",
                    text: "Codex 每周额度才用 \(pct(su))%，还有大量余量，可放心多用。"
                ))
            }
        }

        // B. Anti-waste (model choice) — Opus on tiny replies.
        let opus = claudeEvents.filter { Pricing.claudeFamily($0.model) == "opus" }
        let opusSmall = opus.filter { $0.outputTokens < thresholds.opusSmallOutputTokens }
        if opus.count >= thresholds.opusMinCalls,
           Double(opusSmall.count) / Double(max(opus.count, 1)) > thresholds.opusSmallShare {
            tips.append(Tip(
                severity: .warn, category: "省钱",
                text: "有 \(opusSmall.count) 次 Opus 调用输出很短（小任务）。这类任务换 Sonnet/Haiku，成本可降约 5×。"
            ))
        }

        // C. Anti-waste (cache hit rate)
        let cl = aggregation.claude
        let denom = cl.inputTokens + cl.cacheReadTokens + cl.cacheWriteTokens
        if denom > thresholds.claudeCacheDenomMin {
            let ratio = Double(cl.cacheReadTokens) / Double(denom)
            if ratio < thresholds.cacheLowShare {
                tips.append(Tip(
                    severity: .warn, category: "省钱",
                    text: "Claude 缓存读取占比仅 \(pct(ratio * 100))%。固定 CLAUDE.md、复用稳定上下文可大幅省输入成本。"
                ))
            } else if ratio > thresholds.cacheGoodShare {
                tips.append(Tip(
                    severity: .success, category: "做得好",
                    text: "Claude 缓存命中率 \(pct(ratio * 100))%，缓存用得不错。"
                ))
            }
        }

        // D. Value (equivalent $ vs subscription price)
        let (cost7, _) = Aggregator.windowUsage(claudeEvents, days: 7, now: now)
        if let plan = planPriceUSD, plan > 0, cost7 > 0 {
            let mult = cost7 / plan
            let multStr = mult < 0.1 ? "<0.1×" : String(format: "%.1f×", mult)
            let monthlyEst = cost7 / 7 * 30
            tips.append(Tip(
                severity: .info, category: "价值",
                text: "近7天 Claude 等效用量 ≈ \(Formatting.usd(cost7))（折月≈\(Formatting.usd(monthlyEst))），对比月付 \(Formatting.usd(plan)) 约 \(multStr) 价值（仅 Claude 部分）。"
            ))
        }

        // E. Anti-overuse (Claude 5h burst)
        let (cost5h, _) = Aggregator.windowUsage(claudeEvents, hours: 5, now: now)
        let avg5h = cost7 > 0 ? cost7 / (7 * 24 / 5) : 0
        if avg5h > 0, cost5h > thresholds.overUseMultiple * avg5h, cost5h > thresholds.overUseMinUSD {
            tips.append(Tip(
                severity: .warn, category: "防过度",
                text: "最近5小时 Claude 用量（≈\(Formatting.usd(cost5h))）明显高于你的平时节奏，注意别在短时间内冲顶 5 小时窗口。"
            ))
        }

        if tips.isEmpty {
            tips.append(Tip(severity: .info, category: "提示", text: "暂无明显问题。数据越多，建议越准。"))
        }
        return tips
    }

    /// Round-to-integer percent like Python's `{:.0f}`.
    private static func pct(_ x: Double) -> String {
        String(format: "%.0f", x)
    }
}
