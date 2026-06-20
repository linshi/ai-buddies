import Foundation

/// Parses Codex logs at `~/.codex/sessions/**/rollout-*.jsonl`.
/// Ported from `usage_buddy.py` `scan_codex`.
public enum CodexParser {

    public static let defaultDirectory = "~/.codex/sessions"

    public struct Result: Sendable {
        public let events: [UsageEvent]
        /// Authoritative quota (globally latest `rate_limits`).
        public let rateLimit: DatedRateLimits?
        public let filesSeen: Int
        /// Count of rollouts that look like sub-agent replays of parent history.
        public let subagentSuspect: Int
    }

    public static func scan(directory: String, since: Date? = nil) -> Result {
        let base = (directory as NSString).expandingTildeInPath
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: base, isDirectory: &isDir), isDir.boolValue else {
            return Result(events: [], rateLimit: nil, filesSeen: 0, subagentSuspect: 0)
        }

        var perSession: [String: UsageEvent] = [:]
        var latest: DatedRateLimits?
        var filesSeen = 0
        var subagentSuspect = 0

        let baseURL = URL(fileURLWithPath: base)
        guard let enumerator = fm.enumerator(at: baseURL, includingPropertiesForKeys: nil) else {
            return Result(events: [], rateLimit: nil, filesSeen: 0, subagentSuspect: 0)
        }

        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("rollout-"), fileURL.pathExtension == "jsonl" else { continue }
            filesSeen += 1
            let sid = fileURL.deletingPathExtension().lastPathComponent

            var model = "unknown"
            var bestTotal = -1
            var best: UsageEvent?
            var firstTokenCountTS: Date?
            var tokenCountCount = 0
            var fileHasFirstTS = false

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let obj = ParsingSupport.jsonObject(line) else { continue }
                let type = obj["type"] as? String
                let payload = obj["payload"] as? [String: Any] ?? [:]
                let ts = ParsingSupport.parseTimestamp(obj["timestamp"] ?? payload["timestamp"])

                if type == "session_meta" {
                    if let m = (payload["model"] as? String) ?? (payload["model_slug"] as? String) {
                        model = m
                    }
                }

                guard type == "event_msg", (payload["type"] as? String) == "token_count" else { continue }

                tokenCountCount += 1
                if !fileHasFirstTS {
                    firstTokenCountTS = ts
                    fileHasFirstTS = true
                }

                let info = payload["info"] as? [String: Any] ?? [:]
                let total = info["total_token_usage"] as? [String: Any] ?? [:]

                let inTok = ParsingSupport.int(total["input_tokens"])
                let outTok = ParsingSupport.int(total["output_tokens"])
                let crTok = ParsingSupport.int(total["cached_input_tokens"] ?? total["cache_read_input_tokens"])
                let reasoning = ParsingSupport.int(total["reasoning_output_tokens"] ?? total["reasoning_tokens"])
                let totalTok = ParsingSupport.int(total["total_tokens"])

                // Keep the cumulative maximum for this session.
                if totalTok >= bestTotal {
                    bestTotal = totalTok
                    best = UsageEvent(
                        provider: .codex,
                        timestamp: ts,
                        project: sid,
                        model: model,
                        inputTokens: inTok,
                        outputTokens: outTok,
                        cacheReadTokens: crTok,
                        cacheWriteTokens: 0,
                        sessionId: sid,
                        totalTokens: totalTok,
                        reasoningTokens: reasoning
                    )
                }

                // Globally latest rate_limits wins.
                if let rlDict = (payload["rate_limits"] as? [String: Any]) ?? (info["rate_limits"] as? [String: Any]) {
                    let limits = parseRateLimits(rlDict)
                    if latest == nil {
                        latest = DatedRateLimits(timestamp: ts, limits: limits)
                    } else if let ts, let prev = latest?.timestamp, ts > prev {
                        latest = DatedRateLimits(timestamp: ts, limits: limits)
                    } else if latest?.timestamp == nil {
                        latest = DatedRateLimits(timestamp: ts, limits: limits)
                    }
                }
            }

            // Sub-agent heuristic: many token_count events clustered at the session's
            // first moment ⇒ replay of parent history.
            if tokenCountCount >= 3, let first = firstTokenCountTS, let b = best, b.timestamp == first {
                subagentSuspect += 1
            }

            if var b = best {
                // model may have been discovered after the best event; patch it in.
                if b.model != model, model != "unknown" {
                    b = UsageEvent(
                        provider: .codex, timestamp: b.timestamp, project: b.project, model: model,
                        inputTokens: b.inputTokens, outputTokens: b.outputTokens,
                        cacheReadTokens: b.cacheReadTokens, cacheWriteTokens: 0,
                        sessionId: b.sessionId, totalTokens: b.totalTokens, reasoningTokens: b.reasoningTokens
                    )
                }
                perSession[sid] = b
            }
        }

        var events: [UsageEvent] = []
        for event in perSession.values {
            if let since, let ts = event.timestamp, ts < since { continue }
            events.append(event)
        }
        return Result(events: events, rateLimit: latest, filesSeen: filesSeen, subagentSuspect: subagentSuspect)
    }

    private static func parseRateLimits(_ dict: [String: Any]) -> RateLimits {
        func window(_ key: String) -> RateLimitWindow? {
            guard let w = dict[key] as? [String: Any] else { return nil }
            return RateLimitWindow(
                usedPercent: ParsingSupport.double(w["used_percent"]),
                windowMinutes: (w["window_minutes"]).map { ParsingSupport.int($0) },
                resetsInSeconds: ParsingSupport.double(w["resets_in_seconds"])
            )
        }
        return RateLimits(primary: window("primary"), secondary: window("secondary"))
    }
}
