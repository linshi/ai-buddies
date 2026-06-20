import Foundation
import UsageCore
import UserNotifications

/// iOS app state. Reads the `Snapshot` from CloudKit (published by the Mac),
/// caches it in the App Group for the widget, and falls back to that cache offline.
@MainActor
final class IOSModel: ObservableObject {

    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdated: Date?

    let settings = SettingsStore()
    private let sync = CloudSync()
    private let isDemo = ProcessInfo.processInfo.environment["AIBUDDIES_DEMO"] == "1"

    init() {
        if isDemo {
            snapshot = .sample()
        } else {
            // Show the cached snapshot immediately, then refresh from CloudKit.
            snapshot = SnapshotStore.load()
        }
        lastUpdated = snapshot?.generatedAt
    }

    func start() {
        guard !isDemo else { return }
        Task {
            await refresh()
            if CloudGate.isEnabled { try? await sync.subscribeForChanges() }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func refresh() async {
        guard !isDemo else { return }
        guard !isLoading else { return }
        guard CloudGate.isEnabled else {
            // Unsigned verification build: show whatever the App Group cache holds.
            if snapshot == nil {
                lastError = "暂无数据。请先在 Mac 上打开 AI Buddies 并完成一次刷新以同步。"
            }
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await sync.fetchLatest()
            snapshot = snap
            lastUpdated = snap.generatedAt
            lastError = nil
            SnapshotStore.save(snap)   // refresh widget cache
        } catch {
            // Keep showing cache; surface a friendly message.
            if snapshot == nil {
                lastError = "暂无数据。请先在 Mac 上打开 AI Buddies 并完成一次刷新以同步。"
            }
        }
    }

    func window(_ provider: Provider, _ kind: WindowKind) -> WindowState? {
        snapshot?.windows.first { $0.provider == provider && $0.kind == kind }
    }

    /// Combined cost for a horizon (today or this week) from byDay.
    func cost(today: Bool) -> Double {
        guard let snapshot else { return 0 }
        if today {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
            let key = f.string(from: Date())
            return snapshot.byDay.first { $0.day == key }?.equivCostUSD ?? 0
        } else {
            return snapshot.byDay.suffix(7).reduce(0) { $0 + $1.equivCostUSD }
        }
    }

    var topTip: Tip? {
        snapshot?.tips.min { $0.severity.rank < $1.severity.rank }
    }
}
