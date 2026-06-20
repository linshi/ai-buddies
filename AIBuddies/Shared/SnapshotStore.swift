import Foundation
import UsageCore

/// Shared App Group store for the latest `Snapshot`, read by widgets and the iOS app.
public enum SnapshotStore {

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// File URL inside the App Group container (nil if the group isn't provisioned).
    public static func fileURL(appGroup: String = AppConstants.appGroup) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(AppConstants.snapshotFileName)
    }

    @discardableResult
    public static func save(_ snapshot: Snapshot, appGroup: String = AppConstants.appGroup) -> Bool {
        guard let url = fileURL(appGroup: appGroup),
              let data = try? encoder.encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    public static func load(appGroup: String = AppConstants.appGroup) -> Snapshot? {
        guard let url = fileURL(appGroup: appGroup),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Snapshot.self, from: data)
    }

    /// Encode/decode helpers reused by the CloudKit transport.
    public static func encode(_ snapshot: Snapshot) -> Data? { try? encoder.encode(snapshot) }
    public static func decode(_ data: Data) -> Snapshot? { try? decoder.decode(Snapshot.self, from: data) }
}
