import Foundation
import UsageCore

// Minimal CLI used to (a) calibrate the Swift port against usage_buddy.py on real
// data, and (b) emit a Snapshot JSON. Mirrors the Python tool's defaults.
//
//   swift run usage-cli                 # human report
//   swift run usage-cli --json          # snapshot JSON
//   swift run usage-cli --plan-price 200

let args = CommandLine.arguments
var planPrice: Double?
var jsonOnly = false
var days: Double?
var i = 1
while i < args.count {
    switch args[i] {
    case "--plan-price": i += 1; planPrice = Double(args[safe: i] ?? "")
    case "--days": i += 1; days = Double(args[safe: i] ?? "")
    case "--json": jsonOnly = true
    default: break
    }
    i += 1
}

let since = days.map { Date().addingTimeInterval(-$0 * 86400) }
let claude = ClaudeParser.scan(directories: ClaudeParser.defaultDirectories, since: since)
let codex = CodexParser.scan(directory: CodexParser.defaultDirectory, since: since)

let snapshot = SnapshotBuilder.build(
    .init(
        claudeEvents: claude.events,
        codexEvents: codex.events,
        codexRateLimit: codex.rateLimit,
        subagentSuspect: codex.subagentSuspect,
        planPriceUSD: planPrice
    )
)

if jsonOnly {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(snapshot), let s = String(data: data, encoding: .utf8) {
        print(s)
    }
} else {
    print("─────────────────────────────────────────")
    print("  AI Buddies (Swift UsageCore) — 校准报告")
    print("─────────────────────────────────────────")
    let c = snapshot.claude
    print("▌Claude  (\(claude.filesSeen) files, \(c.calls) calls)")
    print("   equiv cost   \(Formatting.usd(c.equivCostUSD))")
    print("   in \(c.inputTokens)  out \(c.outputTokens)  cr \(c.cacheReadTokens)  cw \(c.cacheWriteTokens)")
    print("   5h(est) \(Formatting.usd(c.window5hEstimate.equivCostUSD)) / \(c.window5hEstimate.tokens) tok")
    print("   7d(est) \(Formatting.usd(c.window7dEstimate.equivCostUSD)) / \(c.window7dEstimate.tokens) tok")
    let x = snapshot.codex
    print("▌Codex   (\(codex.filesSeen) files, \(x.sessions) sessions, subagent-suspect \(snapshot.subagentSuspect))")
    print("   equiv cost≈ \(Formatting.usd(x.equivCostUSDApprox))")
    print("   in \(x.inputTokens)  out \(x.outputTokens)  cr \(x.cacheReadTokens)")
    for w in snapshot.windows where w.provider == .codex {
        let pct = w.usedPercent.map { String(format: "%.0f%%", $0) } ?? "?"
        print("   \(w.kind) used \(pct)  resets \(Formatting.humanDuration(w.resetsAt.map { $0.timeIntervalSinceNow }))  (authoritative)")
    }
    print("▌Top models")
    for m in snapshot.byModel.prefix(8) {
        print("   \(m.name)  \(Formatting.usd(m.equivCostUSD))  \(m.tokens) tok")
    }
    print("▌Tips")
    for t in snapshot.tips { print("   [\(t.severity.rawValue)] \(t.category)  \(t.text)") }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
