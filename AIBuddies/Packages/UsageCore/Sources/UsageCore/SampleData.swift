import Foundation

public extension Snapshot {

    /// A representative snapshot for SwiftUI previews, widget placeholders, and
    /// `--demo` screenshot runs. Dates are relative to `now` so "today/this week"
    /// render meaningfully. Project names are generic (no real paths).
    static func sample(now: Date = Date()) -> Snapshot {
        let cal = Calendar.current
        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.dateFormat = "yyyy-MM-dd"

        let dayCosts: [(Double, Double)] = [   // (claude, codex)
            (6.20, 3.10), (9.80, 4.40), (4.50, 2.10), (12.30, 5.60),
            (7.10, 3.80), (10.40, 4.90), (8.70, 4.20),
        ]
        let byDay: [DayUsage] = dayCosts.enumerated().map { idx, pair in
            let date = cal.date(byAdding: .day, value: -(6 - idx), to: now) ?? now
            let total = pair.0 + pair.1
            return DayUsage(
                day: dayFmt.string(from: date),
                equivCostUSD: total,
                tokens: Int(total * 2_500_000),
                claudeCostUSD: pair.0,
                codexCostUSD: pair.1
            )
        }

        let windows: [WindowState] = [
            WindowState(provider: .codex, kind: .fiveHour, usedPercent: 42,
                        resetsAt: now.addingTimeInterval(2.4 * 3600), isEstimated: false, windowMinutes: 300),
            WindowState(provider: .codex, kind: .weekly, usedPercent: 18,
                        resetsAt: now.addingTimeInterval(4 * 86400), isEstimated: false, windowMinutes: 10080),
            WindowState(provider: .claude, kind: .fiveHour, usedPercent: 61,
                        resetsAt: now.addingTimeInterval(3 * 3600), isEstimated: true, windowMinutes: 300),
            WindowState(provider: .claude, kind: .weekly, usedPercent: 47,
                        resetsAt: now.addingTimeInterval(5 * 86400), isEstimated: true, windowMinutes: 10080),
        ]

        let tips: [Tip] = [
            Tip(severity: .warn, category: "防限流", text: "Codex 5小时额度已用 78%，约 1小时20分后重置，建议先合并/暂缓重任务。"),
            Tip(severity: .warn, category: "省钱", text: "有 14 次 Opus 调用输出很短（小任务）。这类任务换 Sonnet/Haiku，成本可降约 5×。"),
            Tip(severity: .success, category: "做得好", text: "Claude 缓存命中率 88%，缓存用得不错。"),
            Tip(severity: .info, category: "价值", text: "近7天 Claude 等效用量 ≈ $58.00（折月≈$248.57），对比月付 $200.00 约 1.2× 价值（仅 Claude 部分）。"),
        ]

        return Snapshot(
            generatedAt: now,
            claude: ClaudeSummary(
                calls: 1_284,
                inputTokens: 5_120_000, outputTokens: 1_840_000,
                cacheReadTokens: 96_400_000, cacheWriteTokens: 7_300_000,
                equivCostUSD: 58.0,
                window5hEstimate: .init(equivCostUSD: 2.66, tokens: 1_840_000, authoritative: false),
                window7dEstimate: .init(equivCostUSD: 58.0, tokens: 96_400_000, authoritative: false)
            ),
            codex: CodexSummary(
                sessions: 96,
                inputTokens: 41_000_000, outputTokens: 980_000, cacheReadTokens: 22_300_000,
                equivCostUSDApprox: 28.1, priceIsApprox: true
            ),
            windows: windows,
            subagentSuspect: 2,
            byModel: [
                ModelUsage(name: "claude/opus", tokens: 78_000_000, equivCostUSD: 49.2),
                ModelUsage(name: "codex/gpt-5-codex", tokens: 64_000_000, equivCostUSD: 28.1),
                ModelUsage(name: "claude/sonnet", tokens: 22_000_000, equivCostUSD: 8.4),
                ModelUsage(name: "claude/haiku", tokens: 4_000_000, equivCostUSD: 0.4),
            ],
            byProjectTop: [
                ProjectUsage(name: "[C] my-web-app", tokens: 31_000_000, equivCostUSD: 21.4, provider: .claude),
                ProjectUsage(name: "[X] rollout-2026-06-18", tokens: 18_000_000, equivCostUSD: 12.7, provider: .codex),
                ProjectUsage(name: "[C] data-pipeline", tokens: 14_000_000, equivCostUSD: 9.8, provider: .claude),
                ProjectUsage(name: "[C] mobile-client", tokens: 9_000_000, equivCostUSD: 6.1, provider: .claude),
                ProjectUsage(name: "[X] rollout-2026-06-17", tokens: 7_000_000, equivCostUSD: 4.9, provider: .codex),
            ],
            byDay: byDay,
            tips: tips,
            planPriceUSD: 200
        )
    }
}
