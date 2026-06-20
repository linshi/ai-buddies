import Foundation
import CloudKit
import Security
import UsageCore

/// CloudKit transport for the unified `Snapshot` (spec §7).
///
/// Single-writer model: the Mac publishes; iOS reads. To keep things robust and
/// well under the free tier, the whole snapshot is stored as one record
/// (`Snapshot`/`current`) carrying a JSON asset, with per-day `DailyRollup`
/// records for lightweight history/queryability.
public final class CloudSync {

    public enum SyncError: Error { case unavailable, notSignedIn, encodeFailed, noRecord }

    private let containerIdentifier: String
    /// Lazily created — never touch `CKContainer` unless the iCloud entitlement is
    /// present, otherwise CloudKit raises an uncatchable exception (e.g. an unsigned
    /// or unprovisioned build). In that case all ops fail softly.
    private lazy var container: CKContainer? =
        Self.isEntitled ? CKContainer(identifier: containerIdentifier) : nil
    /// Private DB by default (spec privacy model). When the public-DB bridge is
    /// enabled (`CloudGate.usePublicDatabase`), use the container's public DB so two
    /// of the user's own iCloud accounts (e.g. a build Mac + a personal phone) can share.
    private var database: CKDatabase? {
        guard let container else { return nil }
        return CloudGate.usePublicDatabase ? container.publicCloudDatabase : container.privateCloudDatabase
    }

    public static let snapshotRecordType = "Snapshot"
    public static let snapshotRecordName = "current"
    public static let dailyRollupRecordType = "DailyRollup"

    public init(containerIdentifier: String = AppConstants.cloudKitContainer) {
        self.containerIdentifier = containerIdentifier
    }

    /// Whether the running binary carries the CloudKit entitlement.
    public static let isEntitled: Bool = {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil)
        return value != nil
        #else
        return true
        #endif
    }()

    public var isAvailable: Bool { Self.isEntitled }

    private func requireDatabase() throws -> CKDatabase {
        guard let database else { throw SyncError.unavailable }
        return database
    }

    public func accountAvailable() async -> Bool {
        guard let container else { return false }
        return (try? await container.accountStatus()) == .available
    }

    // MARK: - Publish (Mac)

    public func publish(_ snapshot: Snapshot) async throws {
        let database = try requireDatabase()
        guard await accountAvailable() else { throw SyncError.notSignedIn }
        guard let data = SnapshotStore.encode(snapshot) else { throw SyncError.encodeFailed }

        let recordID = CKRecord.ID(recordName: Self.snapshotRecordName)
        let record = (try? await database.record(for: recordID))
            ?? CKRecord(recordType: Self.snapshotRecordType, recordID: recordID)

        // Store JSON as an asset to avoid field-size limits.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: tmp)
        record["json"] = CKAsset(fileURL: tmp)
        record["updatedAt"] = snapshot.generatedAt as NSDate

        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        try? FileManager.default.removeItem(at: tmp)

        try await publishDailyRollups(snapshot)
    }

    private func publishDailyRollups(_ snapshot: Snapshot) async throws {
        let database = try requireDatabase()
        let records: [CKRecord] = snapshot.byDay.suffix(35).map { day in
            let id = CKRecord.ID(recordName: "rollup-\(day.day)")
            let r = CKRecord(recordType: Self.dailyRollupRecordType, recordID: id)
            r["date"] = day.day as NSString
            r["claudeCost"] = day.claudeCostUSD as NSNumber
            r["codexCost"] = day.codexCostUSD as NSNumber
            r["totalCost"] = day.equivCostUSD as NSNumber
            r["tokens"] = day.tokens as NSNumber
            return r
        }
        guard !records.isEmpty else { return }
        _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
    }

    // MARK: - Fetch (iOS)

    public func fetchLatest() async throws -> Snapshot {
        let database = try requireDatabase()
        let recordID = CKRecord.ID(recordName: Self.snapshotRecordName)
        let record = try await database.record(for: recordID)
        guard let asset = record["json"] as? CKAsset,
              let url = asset.fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = SnapshotStore.decode(data) else {
            throw SyncError.noRecord
        }
        return snapshot
    }

    // MARK: - Subscribe (iOS) — push on snapshot change

    public func subscribeForChanges() async throws {
        let database = try requireDatabase()
        let subID = "snapshot-changes"
        let existing = try? await database.allSubscriptions()
        if existing?.contains(where: { $0.subscriptionID == subID }) == true { return }

        let subscription = CKQuerySubscription(
            recordType: Self.snapshotRecordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // silent push to refresh
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }
}

/// Decides whether CloudKit may be touched. Disabled when the process is launched
/// with `AIBUDDIES_NO_CLOUD=1` (used by unsigned UI-verification runs) so the app
/// renders its empty/cached state instead of trapping in CloudKit. Always enabled
/// in normal (signed) builds.
public enum CloudGate {
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["AIBUDDIES_NO_CLOUD"] != "1"
    }

    /// Opt-in public-DB bridge for syncing across two of the user's own iCloud
    /// accounts. Enabled by the persisted setting or the `AIBUDDIES_PUBLIC_DB=1`
    /// env override. Default off → private database (E2E private, spec default).
    public static let publicDatabaseDefaultsKey = "usePublicDatabase"
    public static var usePublicDatabase: Bool {
        if ProcessInfo.processInfo.environment["AIBUDDIES_PUBLIC_DB"] == "1" { return true }
        return UserDefaults.standard.bool(forKey: publicDatabaseDefaultsKey)
    }
}
