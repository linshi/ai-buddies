import Foundation
import UsageCore

/// Mac-side publisher: pushes each new `Snapshot` to CloudKit and caches it in the
/// App Group container. Best-effort — failures (e.g. no iCloud / no provisioning)
/// are logged and never block the local UI.
final class CloudPublisher {
    private let sync = CloudSync()

    func publish(_ snapshot: Snapshot) {
        SnapshotStore.save(snapshot)   // local App Group cache (for a Mac widget)
        Task {
            do {
                try await sync.publish(snapshot)
            } catch {
                NSLog("[CloudPublisher] publish skipped: \(error)")
            }
        }
    }
}
