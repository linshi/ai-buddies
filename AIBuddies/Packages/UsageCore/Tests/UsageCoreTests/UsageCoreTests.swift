import XCTest
@testable import UsageCore

final class UsageCoreTests: XCTestCase {

    // Fixed reference clock so window math is deterministic.
    let now: Date = ISO8601DateFormatter().date(from: "2026-06-19T12:00:00Z")!

    private func fixtures() -> URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
    }
    private func claudeDir() -> String { fixtures().appendingPathComponent("claude").path }
    private func codexMainDir() -> String { fixtures().appendingPathComponent("codex_main").path }
    private func codexSubDir() -> String { fixtures().appendingPathComponent("codex_subagent").path }

    // MARK: - Claude parsing & de-dup

    func testClaudeDedupKeepsFinalUsage() {
        let result = ClaudeParser.scan(directories: [claudeDir()])
        // 2 unique messages (streaming placeholder for m1 collapsed into final).
        XCTAssertEqual(result.events.count, 2)

        let agg = Aggregator.aggregate(claude: result.events, codex: [])
        XCTAssertEqual(agg.claude.calls, 2)
        XCTAssertEqual(agg.claude.inputTokens, 150)   // 100 (final, not 1) + 50
        XCTAssertEqual(agg.claude.outputTokens, 800)  // 500 + 300
        XCTAssertEqual(agg.claude.cacheReadTokens, 6000)
        XCTAssertEqual(agg.claude.cacheWriteTokens, 200)

        // Cost: opus(0.0145) + sonnet(0.00615) = 0.0209
        XCTAssertEqual(agg.claude.cost, 0.0209, accuracy: 1e-9)
        XCTAssertEqual(result.events.first(where: { $0.project == "myproj" })?.project, "myproj")
        XCTAssertEqual(agg.byProject["[C] myproj"]?.cost ?? 0, 0.0209, accuracy: 1e-9)
    }

    func testClaudeModelFamilies() {
        let agg = Aggregator.aggregate(
            claude: ClaudeParser.scan(directories: [claudeDir()]).events, codex: []
        )
        XCTAssertNotNil(agg.byModel["claude/opus"])
        XCTAssertNotNil(agg.byModel["claude/sonnet"])
    }

    // MARK: - Claude window proxy

    func testClaudeWindowUsage() {
        let events = ClaudeParser.scan(directories: [claudeDir()]).events
        let w5 = Aggregator.windowUsage(events, hours: 5, now: now)
        XCTAssertEqual(w5.cost, 0.0209, accuracy: 1e-9)
        XCTAssertEqual(w5.tokens, 7150)   // 150+800+6000+200

        // A 1-hour window excludes the 10:00 (opus) event, keeps 11:00 (sonnet).
        let w1 = Aggregator.windowUsage(events, hours: 1.5, now: now)
        XCTAssertEqual(w1.cost, 0.00615, accuracy: 1e-9)
    }

    // MARK: - Codex parsing & authoritative quota

    func testCodexCumulativeMaxAndRateLimits() {
        let result = CodexParser.scan(directory: codexMainDir())
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.subagentSuspect, 0)

        let e = result.events[0]
        XCTAssertEqual(e.inputTokens, 1500)   // cumulative max event, not the 1000 one
        XCTAssertEqual(e.outputTokens, 1000)
        XCTAssertEqual(e.cacheReadTokens, 500)
        XCTAssertEqual(e.totalTokens, 3000)
        XCTAssertEqual(e.reasoningTokens, 200)
        XCTAssertEqual(e.model, "gpt-5-codex")
        XCTAssertEqual(e.tokenCount, 3000)

        let rl = result.rateLimit
        XCTAssertNotNil(rl)
        XCTAssertEqual(rl?.limits.primary?.usedPercent, 40)
        XCTAssertEqual(rl?.limits.secondary?.usedPercent, 20)
        XCTAssertEqual(rl?.limits.primary?.resetsInSeconds, 3600)
    }

    func testCodexCostApprox() {
        let result = CodexParser.scan(directory: codexMainDir())
        let agg = Aggregator.aggregate(claude: [], codex: result.events)
        // 1500*1.25e-6 + 1000*10e-6 + 500*0.125e-6 = 0.0119375
        XCTAssertEqual(agg.codex.cost, 0.0119375, accuracy: 1e-9)
        XCTAssertEqual(agg.codex.sessions, 1)
    }

    func testCodexSubagentDetection() {
        let result = CodexParser.scan(directory: codexSubDir())
        XCTAssertEqual(result.subagentSuspect, 1)
        XCTAssertEqual(result.events.count, 1)   // still counted, just flagged
    }

    // MARK: - Window engine

    func testCodexWindowsAuthoritative() {
        let rl = CodexParser.scan(directory: codexMainDir()).rateLimit
        let windows = WindowEngine.codexWindows(rl, now: now)
        XCTAssertEqual(windows.count, 2)
        let five = windows.first { $0.kind == .fiveHour }
        XCTAssertEqual(five?.isEstimated, false)
        XCTAssertEqual(five?.usedPercent, 40)
        XCTAssertEqual(five?.status, .green)
        XCTAssertEqual(five?.resetsAt, now.addingTimeInterval(3600))
    }

    func testClaudeWindowsEstimatedWithCeiling() {
        let events = ClaudeParser.scan(directories: [claudeDir()]).events
        // With a tiny ceiling the estimated percent should be capped at 100.
        let windows = WindowEngine.claudeEstimatedWindows(
            events, fiveHourCeilingUSD: 0.001, weeklyCeilingUSD: 1.0, now: now
        )
        let five = windows.first { $0.kind == .fiveHour }
        XCTAssertEqual(five?.isEstimated, true)
        XCTAssertEqual(five?.usedPercent, 100)   // capped
        let week = windows.first { $0.kind == .weekly }
        XCTAssertEqual(week?.usedPercent ?? 0, 2.09, accuracy: 1e-6)  // 0.0209/1.0*100
    }

    func testWindowStatusThresholds() {
        func st(_ p: Double) -> WindowState.Status {
            WindowState(provider: .codex, kind: .fiveHour, usedPercent: p, resetsAt: nil, isEstimated: false).status
        }
        XCTAssertEqual(st(50), .green)
        XCTAssertEqual(st(75), .amber)
        XCTAssertEqual(st(95), .red)
    }

    // MARK: - Tips engine

    func testTipsAntiThrottleDanger() {
        let rl = DatedRateLimits(
            timestamp: now,
            limits: RateLimits(
                primary: RateLimitWindow(usedPercent: 85, windowMinutes: 300, resetsInSeconds: 1800),
                secondary: RateLimitWindow(usedPercent: 78, windowMinutes: 10080, resetsInSeconds: 100000)
            )
        )
        let tips = TipsEngine.build(
            claudeEvents: [], codexEvents: [],
            aggregation: Aggregation(), codexRateLimit: rl, planPriceUSD: nil, now: now
        )
        XCTAssertTrue(tips.contains { $0.severity == .danger && $0.category == "防限流" })
        XCTAssertTrue(tips.contains { $0.severity == .warn && $0.category == "防限流" })
    }

    func testTipsIdleSuccess() {
        let rl = DatedRateLimits(
            timestamp: now,
            limits: RateLimits(
                primary: RateLimitWindow(usedPercent: 10, windowMinutes: 300, resetsInSeconds: 100),
                secondary: RateLimitWindow(usedPercent: 12, windowMinutes: 10080, resetsInSeconds: 100)
            )
        )
        let tips = TipsEngine.build(
            claudeEvents: [], codexEvents: [],
            aggregation: Aggregation(), codexRateLimit: rl, planPriceUSD: nil, now: now
        )
        XCTAssertTrue(tips.contains { $0.severity == .success && $0.category == "防闲置" })
    }

    func testTipsOpusSmallTasks() {
        // 12 opus calls, all with tiny output ⇒ "省钱" warning.
        let events = (0..<12).map { i in
            UsageEvent(provider: .claude, timestamp: now, project: "p",
                       model: "claude-opus-4", inputTokens: 100, outputTokens: 50,
                       cacheReadTokens: 0, cacheWriteTokens: 0, sessionId: "s\(i)")
        }
        let agg = Aggregator.aggregate(claude: events, codex: [])
        let tips = TipsEngine.build(
            claudeEvents: events, codexEvents: [],
            aggregation: agg, codexRateLimit: nil, planPriceUSD: nil, now: now
        )
        XCTAssertTrue(tips.contains { $0.severity == .warn && $0.category == "省钱" && $0.text.contains("Opus") })
    }

    func testTipsValueWithPlanPrice() {
        let events = ClaudeParser.scan(directories: [claudeDir()]).events
        let agg = Aggregator.aggregate(claude: events, codex: [])
        let tips = TipsEngine.build(
            claudeEvents: events, codexEvents: [],
            aggregation: agg, codexRateLimit: nil, planPriceUSD: 100, now: now
        )
        XCTAssertTrue(tips.contains { $0.category == "价值" && $0.severity == .info })
    }

    func testTipsFallbackWhenEmpty() {
        let tips = TipsEngine.build(
            claudeEvents: [], codexEvents: [],
            aggregation: Aggregation(), codexRateLimit: nil, planPriceUSD: nil, now: now
        )
        XCTAssertEqual(tips.count, 1)
        XCTAssertEqual(tips.first?.category, "提示")
    }

    // MARK: - Snapshot (golden, end to end)

    func testSnapshotBuildAndCodableRoundTrip() throws {
        let claude = ClaudeParser.scan(directories: [claudeDir()])
        let codex = CodexParser.scan(directory: codexMainDir())

        let snapshot = SnapshotBuilder.build(
            .init(
                claudeEvents: claude.events,
                codexEvents: codex.events,
                codexRateLimit: codex.rateLimit,
                subagentSuspect: codex.subagentSuspect,
                planPriceUSD: 200
            ),
            now: now
        )

        XCTAssertEqual(snapshot.claude.calls, 2)
        XCTAssertEqual(snapshot.claude.inputTokens, 150)
        XCTAssertEqual(snapshot.codex.sessions, 1)
        XCTAssertEqual(snapshot.codex.priceIsApprox, true)
        XCTAssertEqual(snapshot.windows.count, 4)   // 2 codex + 2 claude
        XCTAssertEqual(snapshot.byModel.first?.name, "claude/opus")  // highest cost first
        XCTAssertFalse(snapshot.tips.isEmpty)
        XCTAssertEqual(snapshot.byProjectTop.count, 2)

        // Codable round-trip (this is the Mac→CloudKit→iOS carrier).
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Snapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    // MARK: - Pricing / formatting

    func testPricingFamilyMatch() {
        XCTAssertEqual(Pricing.claudeFamily("claude-opus-4-1"), "opus")
        XCTAssertEqual(Pricing.claudeFamily("claude-3-5-sonnet"), "sonnet")
        XCTAssertEqual(Pricing.claudeFamily("claude-haiku"), "haiku")
        XCTAssertEqual(Pricing.claudeFamily("mystery-model"), "sonnet")  // default
    }

    func testSnapshotBuildUsesClaudeCeilingsForEstimatedRings() {
        let claude = ClaudeParser.scan(directories: [claudeDir()])
        let snapshot = SnapshotBuilder.build(
            .init(
                claudeEvents: claude.events,
                codexEvents: [],
                codexRateLimit: nil,
                claudeFiveHourCeilingUSD: 1,
                claudeWeeklyCeilingUSD: 2
            ),
            now: now
        )

        let five = snapshot.windows.first { $0.provider == .claude && $0.kind == .fiveHour }
        let week = snapshot.windows.first { $0.provider == .claude && $0.kind == .weekly }
        XCTAssertEqual(five?.isEstimated, true)
        XCTAssertEqual(five?.usedPercent ?? 0, 2.09, accuracy: 1e-6)
        XCTAssertEqual(week?.isEstimated, true)
        XCTAssertEqual(week?.usedPercent ?? 0, 1.045, accuracy: 1e-6)
    }

    func testFormatting() {
        XCTAssertEqual(Formatting.usd(1234.5), "$1,234.50")
        XCTAssertEqual(Formatting.humanDuration(3900), "1小时5分")
        XCTAssertEqual(Formatting.humanDuration(120), "2分")
        XCTAssertEqual(Formatting.humanDuration(0), "现在")
        XCTAssertEqual(Formatting.humanDuration(nil), "?")
    }
}
