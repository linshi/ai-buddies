import Foundation

/// Builds `WindowState`s for both providers. Ported from spec §4.5.
public enum WindowEngine {

    /// Codex authoritative windows from `rate_limits`.
    /// primary → 5h, secondary → weekly.
    public static func codexWindows(_ rateLimit: DatedRateLimits?, now: Date = Date()) -> [WindowState] {
        guard let rl = rateLimit else { return [] }
        var out: [WindowState] = []

        func make(_ window: RateLimitWindow?, kind: WindowKind) -> WindowState? {
            guard let w = window, w.usedPercent != nil || w.resetsInSeconds != nil else { return nil }
            let resetsAt = w.resetsInSeconds.map { now.addingTimeInterval($0) }
            return WindowState(
                provider: .codex,
                kind: kind,
                usedPercent: w.usedPercent,
                resetsAt: resetsAt,
                isEstimated: false,
                windowMinutes: w.windowMinutes
            )
        }

        if let p = make(rl.limits.primary, kind: .fiveHour) { out.append(p) }
        if let s = make(rl.limits.secondary, kind: .weekly) { out.append(s) }
        return out
    }

    /// Claude estimated windows: usage proxy, no authoritative %, flagged `isEstimated`.
    /// `usedPercent` is left nil unless a plan ceiling is supplied (open question §14.3).
    public static func claudeEstimatedWindows(
        _ claudeEvents: [UsageEvent],
        fiveHourCeilingUSD: Double? = nil,
        weeklyCeilingUSD: Double? = nil,
        now: Date = Date()
    ) -> [WindowState] {
        let (cost5h, _) = Aggregator.windowUsage(claudeEvents, hours: 5, now: now)
        let (cost7d, _) = Aggregator.windowUsage(claudeEvents, days: 7, now: now)

        func pct(_ cost: Double, _ ceiling: Double?) -> Double? {
            guard let c = ceiling, c > 0 else { return nil }
            return min(100, cost / c * 100)
        }

        return [
            WindowState(
                provider: .claude, kind: .fiveHour,
                usedPercent: pct(cost5h, fiveHourCeilingUSD),
                resetsAt: now.addingTimeInterval(5 * 3600),
                isEstimated: true, windowMinutes: 300
            ),
            WindowState(
                provider: .claude, kind: .weekly,
                usedPercent: pct(cost7d, weeklyCeilingUSD),
                resetsAt: now.addingTimeInterval(7 * 86400),
                isEstimated: true, windowMinutes: 7 * 24 * 60
            ),
        ]
    }
}
