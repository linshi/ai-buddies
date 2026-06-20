import Foundation
import UserNotifications
import UsageCore

/// Local notifications when a quota window crosses the alert threshold (spec §9).
/// De-duplicates on "provider + window + reset-cycle" so it alerts once per window.
final class NotificationManager {

    private var notified: Set<String> = []

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    func evaluate(snapshot: Snapshot?, enabled: Bool, threshold: Double) {
        guard enabled, let snapshot else { return }
        for window in snapshot.windows {
            guard let pct = window.usedPercent, pct >= threshold else { continue }
            // Reset-cycle component so a new window cycle re-arms the alert.
            let cycle = window.resetsAt.map { Int($0.timeIntervalSince1970 / 60) } ?? 0
            let key = "\(window.provider.rawValue)#\(window.kind.rawValue)#\(Int(threshold))#\(cycle)"
            guard !notified.contains(key) else { continue }
            notified.insert(key)
            post(window: window, pct: pct)
        }
    }

    private func post(window: WindowState, pct: Double) {
        let content = UNMutableNotificationContent()
        content.title = "\(window.provider.displayName) \(window.kind.displayName)额度提醒"
        let remaining = max(0, 100 - pct)
        let reset = window.resetsAt.map { Formatting.humanDuration($0.timeIntervalSinceNow) } ?? "?"
        content.body = "已用 \(Int(pct))%，剩 \(Int(remaining))%，约 \(reset)后重置。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
