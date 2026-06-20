import Foundation

/// Which AI provider an event/window belongs to.
public enum Provider: String, Codable, Sendable, Hashable {
    case claude
    case codex
}

/// Quota window kinds. Claude exposes 5h + weekly; Codex primary/secondary map to these.
public enum WindowKind: String, Codable, Sendable, Hashable {
    case fiveHour
    case weekly
    case weeklySonnet
}

/// One de-duplicated usage record (a Claude assistant turn, or a Codex session rollup).
///
/// Ported from `usage_buddy.py` `scan_claude` / `scan_codex` records. For Codex,
/// `cacheWriteTokens` is always 0 and `totalTokens`/`reasoningTokens` carry the
/// authoritative cumulative figures.
public struct UsageEvent: Codable, Hashable, Sendable {
    public let provider: Provider
    public let timestamp: Date?
    public let project: String
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int
    public let sessionId: String
    /// Codex cumulative `total_tokens` (authoritative). nil for Claude.
    public let totalTokens: Int?
    /// Codex `reasoning_output_tokens`. nil for Claude.
    public let reasoningTokens: Int?

    public init(
        provider: Provider,
        timestamp: Date?,
        project: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int,
        sessionId: String,
        totalTokens: Int? = nil,
        reasoningTokens: Int? = nil
    ) {
        self.provider = provider
        self.timestamp = timestamp
        self.project = project
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.sessionId = sessionId
        self.totalTokens = totalTokens
        self.reasoningTokens = reasoningTokens
    }

    /// Token count used for aggregation. Mirrors `usage_buddy.py`:
    /// Claude = in+out+cr+cw; Codex = total (fallback in+out+cr).
    public var tokenCount: Int {
        if let totalTokens { return totalTokens }
        return inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }
}

/// A quota window's state. Codex windows are authoritative (`isEstimated == false`);
/// Claude windows are usage-proxy estimates (`isEstimated == true`).
public struct WindowState: Codable, Hashable, Sendable {
    public let provider: Provider
    public let kind: WindowKind
    public let usedPercent: Double?
    public let resetsAt: Date?
    public let isEstimated: Bool
    public let windowMinutes: Int?

    public init(
        provider: Provider,
        kind: WindowKind,
        usedPercent: Double?,
        resetsAt: Date?,
        isEstimated: Bool,
        windowMinutes: Int? = nil
    ) {
        self.provider = provider
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.isEstimated = isEstimated
        self.windowMinutes = windowMinutes
    }

    /// Color status per spec §6.2: <70 green, 70–90 amber, ≥90 red.
    public enum Status: String, Codable, Sendable { case green, amber, red, unknown }

    public var status: Status {
        guard let p = usedPercent else { return .unknown }
        if p >= 90 { return .red }
        if p >= 70 { return .amber }
        return .green
    }
}

/// A coaching tip. Ported from `usage_buddy.py` `build_tips`.
public struct Tip: Codable, Hashable, Sendable, Identifiable {
    public enum Severity: String, Codable, Sendable {
        case danger, warn, info, success

        /// Ordering for "most important first" selection (menu bar / home screen).
        public var rank: Int {
            switch self {
            case .danger: return 0
            case .warn: return 1
            case .info: return 2
            case .success: return 3
            }
        }
    }

    public let severity: Severity
    public let category: String
    public let text: String

    public var id: String { "\(severity.rawValue)|\(category)|\(text)" }

    public init(severity: Severity, category: String, text: String) {
        self.severity = severity
        self.category = category
        self.text = text
    }
}

/// One quota window from a Codex `rate_limits` block.
public struct RateLimitWindow: Codable, Hashable, Sendable {
    public let usedPercent: Double?
    public let windowMinutes: Int?
    public let resetsInSeconds: Double?

    public init(usedPercent: Double?, windowMinutes: Int?, resetsInSeconds: Double?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsInSeconds = resetsInSeconds
    }
}

/// Codex `rate_limits` (authoritative quota source).
public struct RateLimits: Codable, Hashable, Sendable {
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?

    public init(primary: RateLimitWindow?, secondary: RateLimitWindow?) {
        self.primary = primary
        self.secondary = secondary
    }
}

/// Latest rate limits with the timestamp they were observed.
public struct DatedRateLimits: Codable, Hashable, Sendable {
    public let timestamp: Date?
    public let limits: RateLimits

    public init(timestamp: Date?, limits: RateLimits) {
        self.timestamp = timestamp
        self.limits = limits
    }
}
