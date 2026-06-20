import Foundation

/// Parses Claude Code logs at `~/.claude/projects/**/*.jsonl`.
/// Ported from `usage_buddy.py` `scan_claude`.
public enum ClaudeParser {

    /// Default scan locations (spec §main): user projects + Xcode integration dir.
    public static let defaultDirectories = [
        "~/.claude/projects",
        "~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects",
    ]

    public struct Result: Sendable {
        public let events: [UsageEvent]
        public let filesSeen: Int
    }

    /// Scan directories for assistant turns with usage, de-duplicating by
    /// `(message.id, requestId)` and keeping the final (last-written) usage —
    /// streaming `input_tokens` are placeholders, so the final value wins.
    public static func scan(directories: [String], since: Date? = nil) -> Result {
        var dedup: [String: UsageEvent] = [:]
        var fallbackCounter = 0
        var filesSeen = 0
        let fm = FileManager.default

        for dir in directories {
            let base = (dir as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: base, isDirectory: &isDir), isDir.boolValue else { continue }
            let baseURL = URL(fileURLWithPath: base)
            guard let enumerator = fm.enumerator(at: baseURL, includingPropertiesForKeys: nil) else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else { continue }
                filesSeen += 1
                let project = fileURL.deletingLastPathComponent().lastPathComponent
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

                for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                    guard let obj = ParsingSupport.jsonObject(line),
                          (obj["type"] as? String) == "assistant" else { continue }

                    let msg = obj["message"] as? [String: Any] ?? [:]
                    guard let usage = (msg["usage"] as? [String: Any]) ?? (obj["usage"] as? [String: Any]) else {
                        continue
                    }

                    let ts = ParsingSupport.parseTimestamp(obj["timestamp"] ?? msg["timestamp"])
                    let mid = (msg["id"] as? String) ?? (obj["uuid"] as? String) ?? (obj["id"] as? String)
                    let rid = (obj["requestId"] as? String) ?? (obj["request_id"] as? String) ?? ""

                    let key: String
                    if let mid {
                        key = "\(mid)\u{1}\(rid)"
                    } else {
                        fallbackCounter += 1
                        key = "\u{2}fallback\u{1}\(fallbackCounter)"
                    }

                    let sessionId = fileURL.deletingPathExtension().lastPathComponent
                    dedup[key] = UsageEvent(
                        provider: .claude,
                        timestamp: ts,
                        project: project,
                        model: (msg["model"] as? String) ?? "unknown",
                        inputTokens: ParsingSupport.int(usage["input_tokens"]),
                        outputTokens: ParsingSupport.int(usage["output_tokens"]),
                        cacheReadTokens: ParsingSupport.int(usage["cache_read_input_tokens"]),
                        cacheWriteTokens: ParsingSupport.int(usage["cache_creation_input_tokens"]),
                        sessionId: sessionId
                    )
                }
            }
        }

        var events: [UsageEvent] = []
        events.reserveCapacity(dedup.count)
        for event in dedup.values {
            if let since, let ts = event.timestamp, ts < since { continue }
            events.append(event)
        }
        return Result(events: events, filesSeen: filesSeen)
    }
}
