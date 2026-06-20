import Foundation

/// Per-token USD prices for one model family.
public struct TokenPrice: Sendable, Hashable {
    public let input: Double
    public let output: Double
    public let cacheRead: Double
    public let cacheWrite: Double

    public init(input: Double, output: Double, cacheRead: Double, cacheWrite: Double) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }
}

/// Price tables and model-family matching. Ported from `usage_buddy.py`
/// `CLAUDE_PRICES` / `CODEX_PRICES` (USD per token, 2026-06).
///
/// Claude prices are verified; Codex prices are an approximation (see
/// `codexPriceIsApprox`). Designed to be replaced by a LiteLLM-sourced table (P4).
public enum Pricing {
    public static let claude: [String: TokenPrice] = [
        "opus":   TokenPrice(input: 5e-6,  output: 25e-6, cacheRead: 0.5e-6, cacheWrite: 6.25e-6),
        "sonnet": TokenPrice(input: 3e-6,  output: 15e-6, cacheRead: 0.3e-6, cacheWrite: 3.75e-6),
        "haiku":  TokenPrice(input: 1e-6,  output: 5e-6,  cacheRead: 0.1e-6, cacheWrite: 1.25e-6),
    ]

    public static let claudeDefaultFamily = "sonnet"

    public static let codexDefault = TokenPrice(
        input: 1.25e-6, output: 10e-6, cacheRead: 0.125e-6, cacheWrite: 1.25e-6
    )

    /// Codex prices are not officially verified.
    public static let codexPriceIsApprox = true

    /// Map a model string to a Claude price family. Ported from `claude_family`.
    public static func claudeFamily(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("opus") { return "opus" }
        if m.contains("sonnet") { return "sonnet" }
        if m.contains("haiku") { return "haiku" }
        return claudeDefaultFamily
    }

    /// Price table for an event.
    public static func price(for event: UsageEvent) -> TokenPrice {
        switch event.provider {
        case .claude:
            return claude[claudeFamily(event.model)] ?? claude[claudeDefaultFamily]!
        case .codex:
            return codexDefault
        }
    }

    /// Equivalent API cost of an event. Ported from `cost_of`.
    public static func cost(of event: UsageEvent) -> Double {
        let p = price(for: event)
        return Double(event.inputTokens) * p.input
            + Double(event.outputTokens) * p.output
            + Double(event.cacheReadTokens) * p.cacheRead
            + Double(event.cacheWriteTokens) * p.cacheWrite
    }
}
