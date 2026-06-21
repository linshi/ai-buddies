import Foundation
import Combine
import UsageCore

/// Top-level app state: owns settings, folder access, file watching, scheduling,
/// and the current `Snapshot`. Coordinates M1 (menu bar) and M2 (dashboard).
@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false
    @Published var needsFolderAccess: Bool

    let settings = SettingsStore()
    let folders = FolderAccess()
    private let notifier = NotificationManager()
    private let publisher = CloudPublisher()
    private var watcher: FileWatcher?
    private var scheduler: RefreshScheduler?
    private var pipelineStarted = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        needsFolderAccess = !folders.hasAllAccess
        // React to settings that change the refresh cadence or computed cost.
        settings.$refreshInterval
            .dropFirst()
            .sink { [weak self] interval in self?.scheduler?.start(interval: interval.seconds) }
            .store(in: &cancellables)
        settings.$planPriceUSD
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
        settings.$claudePlan
            .dropFirst()
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
    }

    private let isDemo = ProcessInfo.processInfo.environment["AIBUDDIES_DEMO"] == "1"
        || ProcessInfo.processInfo.arguments.contains("--demo")

    /// Begin watching + scheduling if access is granted; otherwise prompt onboarding.
    func start() {
        if isDemo {
            needsFolderAccess = false
            snapshot = .sample()
            lastRefresh = Date()
            return
        }
        guard folders.hasAllAccess else { needsFolderAccess = true; return }
        guard !pipelineStarted else { return }
        pipelineStarted = true
        needsFolderAccess = false
        notifier.requestAuthorization()
        setupWatcher()
        scheduler = RefreshScheduler { [weak self] in Task { await self?.refresh() } }
        scheduler?.start(interval: settings.refreshInterval.seconds)
        Task { await refresh() }
    }

    /// Request access to a folder; once both are granted, start the pipeline.
    func grantAccess(_ slot: FolderAccess.Slot) {
        _ = folders.requestAccess(slot)
        if folders.hasAllAccess {
            start()
        } else {
            objectWillChange.send()
        }
    }

    func resetAccess() {
        watcher?.stop()
        watcher = nil
        scheduler?.stop()
        scheduler = nil
        pipelineStarted = false
        folders.clear()
        snapshot = nil
        needsFolderAccess = true
    }

    private func setupWatcher() {
        var paths: [String] = []
        if let url = folders.resolvedURL(.claude) {
            paths.append(url.appendingPathComponent(AppConstants.claudeProjectsSubpath).path)
        }
        if let url = folders.resolvedURL(.codex) {
            paths.append(url.appendingPathComponent(AppConstants.codexSessionsSubpath).path)
        }
        watcher?.stop()
        watcher = FileWatcher(paths: paths) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        watcher?.start()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let planPrice = settings.planPriceUSD
        let claudeFiveHourCeiling = settings.claudePlan.fiveHourEquivalentCeilingUSD
        let claudeWeeklyCeiling = settings.claudePlan.weeklyEquivalentCeilingUSD
        let folders = self.folders
        let snap = await Task.detached(priority: .utility) {
            folders.withAccess { claudeDirs, codexDir -> Snapshot in
                let claude = ClaudeParser.scan(directories: claudeDirs)
                let codex = codexDir.map { CodexParser.scan(directory: $0) }
                return SnapshotBuilder.build(.init(
                    claudeEvents: claude.events,
                    codexEvents: codex?.events ?? [],
                    codexRateLimit: codex?.rateLimit,
                    subagentSuspect: codex?.subagentSuspect ?? 0,
                    planPriceUSD: planPrice,
                    claudeFiveHourCeilingUSD: claudeFiveHourCeiling,
                    claudeWeeklyCeilingUSD: claudeWeeklyCeiling
                ))
            }
        }.value

        snapshot = snap
        lastRefresh = Date()
        publisher.publish(snap)
        notifier.evaluate(
            snapshot: snap,
            enabled: settings.notificationsEnabled,
            threshold: settings.notificationThreshold
        )
    }

    // MARK: - Derived menu bar presentation

    /// Menu bar title text per the display setting (spec §5.1).
    var menuBarTitle: String {
        guard let snapshot else { return "AI" }
        switch settings.menuBarDisplay {
        case .percent:
            // Claude has no authoritative %; when unavailable, fall back to the
            // 5h estimated equivalent $ rather than showing a placeholder.
            let claudePart: String
            if let c = windowPercent(.claude, .fiveHour, in: snapshot) {
                claudePart = "\(Int(c))%"
            } else {
                claudePart = Formatting.usd(snapshot.claude.window5hEstimate.equivCostUSD)
            }
            let x = windowPercent(.codex, .fiveHour, in: snapshot)
            return "C \(claudePart) · X \(fmtPct(x))"
        case .dollars:
            let today = todayCostUSD(in: snapshot)
            return Formatting.usd(today)
        }
    }

    /// Worst status across both 5h windows, for the menu bar icon tint.
    var menuBarStatus: WindowState.Status {
        guard let snapshot else { return .unknown }
        let statuses = snapshot.windows.map(\.status)
        if statuses.contains(.red) { return .red }
        if statuses.contains(.amber) { return .amber }
        if statuses.contains(.green) { return .green }
        return .unknown
    }

    func window(_ provider: Provider, _ kind: WindowKind, in snapshot: Snapshot) -> WindowState? {
        snapshot.windows.first { $0.provider == provider && $0.kind == kind }
    }

    private func windowPercent(_ provider: Provider, _ kind: WindowKind, in snapshot: Snapshot) -> Double? {
        window(provider, kind, in: snapshot)?.usedPercent
    }

    private func fmtPct(_ p: Double?) -> String { p.map { "\(Int($0))%" } ?? "—" }

    /// Today's combined equivalent cost (local day) from byDay.
    func todayCostUSD(in snapshot: Snapshot) -> Double {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        return snapshot.byDay.first { $0.day == today }?.equivCostUSD ?? 0
    }
}
