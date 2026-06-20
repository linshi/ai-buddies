import Foundation

/// The unified payload passed Mac → CloudKit → iOS → Widget (spec §4.8).
/// Structurally aligned with `usage_buddy.py`'s `usage_snapshot.json`, but richer
/// (tips carry severity; windows are typed `WindowState`s).
public struct Snapshot: Codable, Hashable, Sendable {

    public struct WindowEstimate: Codable, Hashable, Sendable {
        public let equivCostUSD: Double
        public let tokens: Int
        public let authoritative: Bool
    }

    public struct ClaudeSummary: Codable, Hashable, Sendable {
        public let calls: Int
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheReadTokens: Int
        public let cacheWriteTokens: Int
        public let equivCostUSD: Double
        public let window5hEstimate: WindowEstimate
        public let window7dEstimate: WindowEstimate
    }

    public struct CodexSummary: Codable, Hashable, Sendable {
        public let sessions: Int
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheReadTokens: Int
        public let equivCostUSDApprox: Double
        public let priceIsApprox: Bool
    }

    public struct ModelUsage: Codable, Hashable, Sendable {
        public let name: String
        public let tokens: Int
        public let equivCostUSD: Double
    }

    public struct ProjectUsage: Codable, Hashable, Sendable {
        public let name: String
        public let tokens: Int
        public let equivCostUSD: Double
        public let provider: Provider?
    }

    public struct DayUsage: Codable, Hashable, Sendable {
        public let day: String
        public let equivCostUSD: Double
        public let tokens: Int
        public let claudeCostUSD: Double
        public let codexCostUSD: Double
    }

    public let generatedAt: Date
    public let claude: ClaudeSummary
    public let codex: CodexSummary
    public let windows: [WindowState]
    public let subagentSuspect: Int
    public let byModel: [ModelUsage]
    public let byProjectTop: [ProjectUsage]
    public let byDay: [DayUsage]
    public let tips: [Tip]
    public let planPriceUSD: Double?
}

/// Builds a `Snapshot` from raw events — the single entry point for both apps.
public enum SnapshotBuilder {

    public struct Input {
        public var claudeEvents: [UsageEvent]
        public var codexEvents: [UsageEvent]
        public var codexRateLimit: DatedRateLimits?
        public var subagentSuspect: Int
        public var planPriceUSD: Double?
        public var claudeFiveHourCeilingUSD: Double?
        public var claudeWeeklyCeilingUSD: Double?

        public init(
            claudeEvents: [UsageEvent],
            codexEvents: [UsageEvent],
            codexRateLimit: DatedRateLimits?,
            subagentSuspect: Int = 0,
            planPriceUSD: Double? = nil,
            claudeFiveHourCeilingUSD: Double? = nil,
            claudeWeeklyCeilingUSD: Double? = nil
        ) {
            self.claudeEvents = claudeEvents
            self.codexEvents = codexEvents
            self.codexRateLimit = codexRateLimit
            self.subagentSuspect = subagentSuspect
            self.planPriceUSD = planPriceUSD
            self.claudeFiveHourCeilingUSD = claudeFiveHourCeilingUSD
            self.claudeWeeklyCeilingUSD = claudeWeeklyCeilingUSD
        }
    }

    public static func build(_ input: Input, now: Date = Date()) -> Snapshot {
        let agg = Aggregator.aggregate(claude: input.claudeEvents, codex: input.codexEvents)

        let (cost5h, tok5h) = Aggregator.windowUsage(input.claudeEvents, hours: 5, now: now)
        let (cost7d, tok7d) = Aggregator.windowUsage(input.claudeEvents, days: 7, now: now)

        let tips = TipsEngine.build(
            claudeEvents: input.claudeEvents,
            codexEvents: input.codexEvents,
            aggregation: agg,
            codexRateLimit: input.codexRateLimit,
            planPriceUSD: input.planPriceUSD,
            now: now
        )

        var windows = WindowEngine.codexWindows(input.codexRateLimit, now: now)
        windows += WindowEngine.claudeEstimatedWindows(
            input.claudeEvents,
            fiveHourCeilingUSD: input.claudeFiveHourCeilingUSD,
            weeklyCeilingUSD: input.claudeWeeklyCeilingUSD,
            now: now
        )

        let claude = Snapshot.ClaudeSummary(
            calls: agg.claude.calls,
            inputTokens: agg.claude.inputTokens,
            outputTokens: agg.claude.outputTokens,
            cacheReadTokens: agg.claude.cacheReadTokens,
            cacheWriteTokens: agg.claude.cacheWriteTokens,
            equivCostUSD: round4(agg.claude.cost),
            window5hEstimate: .init(equivCostUSD: round4(cost5h), tokens: tok5h, authoritative: false),
            window7dEstimate: .init(equivCostUSD: round4(cost7d), tokens: tok7d, authoritative: false)
        )

        let codex = Snapshot.CodexSummary(
            sessions: agg.codex.sessions,
            inputTokens: agg.codex.inputTokens,
            outputTokens: agg.codex.outputTokens,
            cacheReadTokens: agg.codex.cacheReadTokens,
            equivCostUSDApprox: round4(agg.codex.cost),
            priceIsApprox: Pricing.codexPriceIsApprox
        )

        let byModel = agg.byModel
            .map { Snapshot.ModelUsage(name: $0.key, tokens: $0.value.tokens, equivCostUSD: round4($0.value.cost)) }
            .sorted { sortByCostThenName($0.equivCostUSD, $0.name, $1.equivCostUSD, $1.name) }

        let byProjectTop = agg.byProject
            .map { Snapshot.ProjectUsage(name: $0.key, tokens: $0.value.tokens, equivCostUSD: round4($0.value.cost), provider: $0.value.provider) }
            .sorted { sortByCostThenName($0.equivCostUSD, $0.name, $1.equivCostUSD, $1.name) }
            .prefix(10)
            .map { $0 }

        let byDay = agg.byDay
            .map {
                Snapshot.DayUsage(
                    day: $0.key,
                    equivCostUSD: round4($0.value.cost),
                    tokens: $0.value.tokens,
                    claudeCostUSD: round4($0.value.claudeCost),
                    codexCostUSD: round4($0.value.codexCost)
                )
            }
            .sorted { $0.day < $1.day }

        return Snapshot(
            generatedAt: now,
            claude: claude,
            codex: codex,
            windows: windows,
            subagentSuspect: input.subagentSuspect,
            byModel: byModel,
            byProjectTop: byProjectTop,
            byDay: byDay,
            tips: tips,
            planPriceUSD: input.planPriceUSD
        )
    }

    private static func round4(_ x: Double) -> Double {
        (x * 10_000).rounded() / 10_000
    }

    /// Sort by cost descending, then name ascending for stable ordering.
    private static func sortByCostThenName(_ c1: Double, _ n1: String, _ c2: Double, _ n2: String) -> Bool {
        if c1 != c2 { return c1 > c2 }
        return n1 < n2
    }
}
