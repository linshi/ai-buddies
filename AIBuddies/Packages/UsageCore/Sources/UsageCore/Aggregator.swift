import Foundation

/// Aggregated totals across providers / day / project / model.
/// Ported from `usage_buddy.py` `aggregate` and `window_usage`.
public struct Aggregation: Sendable {

    public struct ClaudeTotals: Sendable {
        public var inputTokens = 0
        public var outputTokens = 0
        public var cacheReadTokens = 0
        public var cacheWriteTokens = 0
        public var cost = 0.0
        public var calls = 0
    }

    public struct CodexTotals: Sendable {
        public var inputTokens = 0
        public var outputTokens = 0
        public var cacheReadTokens = 0
        public var cost = 0.0
        public var sessions = 0
    }

    public struct Bucket: Sendable {
        public var tokens = 0
        public var cost = 0.0
        public var provider: Provider?
    }

    public struct DayBucket: Sendable {
        public var cost = 0.0
        public var tokens = 0
        public var claudeCost = 0.0
        public var codexCost = 0.0
    }

    public var claude = ClaudeTotals()
    public var codex = CodexTotals()
    public var byProject: [String: Bucket] = [:]
    public var byModel: [String: Bucket] = [:]
    public var byDay: [String: DayBucket] = [:]
}

public enum Aggregator {

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"   // local time zone (matches Python .astimezone())
        return f
    }()

    public static func aggregate(claude: [UsageEvent], codex: [UsageEvent]) -> Aggregation {
        var agg = Aggregation()

        for e in claude {
            let family = Pricing.claudeFamily(e.model)
            let cost = Pricing.cost(of: e)
            let tok = e.inputTokens + e.outputTokens + e.cacheReadTokens + e.cacheWriteTokens

            agg.claude.inputTokens += e.inputTokens
            agg.claude.outputTokens += e.outputTokens
            agg.claude.cacheReadTokens += e.cacheReadTokens
            agg.claude.cacheWriteTokens += e.cacheWriteTokens
            agg.claude.cost += cost
            agg.claude.calls += 1

            let projectKey = "[C] \(e.project)"
            var pb = agg.byProject[projectKey] ?? Aggregation.Bucket()
            pb.tokens += tok; pb.cost += cost; pb.provider = .claude
            agg.byProject[projectKey] = pb

            let modelKey = "claude/\(family)"
            var mb = agg.byModel[modelKey] ?? Aggregation.Bucket()
            mb.tokens += tok; mb.cost += cost; mb.provider = .claude
            agg.byModel[modelKey] = mb

            if let ts = e.timestamp {
                let day = dayFormatter.string(from: ts)
                var db = agg.byDay[day] ?? Aggregation.DayBucket()
                db.cost += cost; db.tokens += tok; db.claudeCost += cost
                agg.byDay[day] = db
            }
        }

        for e in codex {
            let cost = Pricing.cost(of: e)
            let tok = e.tokenCount

            agg.codex.inputTokens += e.inputTokens
            agg.codex.outputTokens += e.outputTokens
            agg.codex.cacheReadTokens += e.cacheReadTokens
            agg.codex.cost += cost
            agg.codex.sessions += 1

            let label = String(e.sessionId.prefix(18))
            let projectKey = "[X] \(label)"
            var pb = agg.byProject[projectKey] ?? Aggregation.Bucket()
            pb.tokens += tok; pb.cost += cost; pb.provider = .codex
            agg.byProject[projectKey] = pb

            let modelKey = "codex/\(e.model)"
            var mb = agg.byModel[modelKey] ?? Aggregation.Bucket()
            mb.tokens += tok; mb.cost += cost; mb.provider = .codex
            agg.byModel[modelKey] = mb

            if let ts = e.timestamp {
                let day = dayFormatter.string(from: ts)
                var db = agg.byDay[day] ?? Aggregation.DayBucket()
                db.cost += cost; db.tokens += tok; db.codexCost += cost
                agg.byDay[day] = db
            }
        }

        return agg
    }

    /// Claude usage proxy within a recent window (hours or days). Ported from `window_usage`.
    public static func windowUsage(
        _ claude: [UsageEvent],
        hours: Double? = nil,
        days: Double? = nil,
        now: Date = Date()
    ) -> (cost: Double, tokens: Int) {
        let start: Date
        if let hours {
            start = now.addingTimeInterval(-hours * 3600)
        } else {
            start = now.addingTimeInterval(-(days ?? 0) * 86400)
        }
        var cost = 0.0
        var tok = 0
        for e in claude {
            guard let ts = e.timestamp, ts >= start else { continue }
            cost += Pricing.cost(of: e)
            tok += e.inputTokens + e.outputTokens + e.cacheReadTokens + e.cacheWriteTokens
        }
        return (cost, tok)
    }
}
