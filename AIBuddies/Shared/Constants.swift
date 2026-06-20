import Foundation

/// Cross-app constants (CloudKit container, App Group, default keys).
public enum AppConstants {
    public static let cloudKitContainer = "iCloud.com.example.aibuddies"
    public static let appGroup = "group.com.example.aibuddies"
    public static let snapshotFileName = "snapshot.json"

    /// Default scan subpaths relative to the granted root folders.
    public static let claudeProjectsSubpath = "projects"
    public static let codexSessionsSubpath = "sessions"
}
