import Foundation
import AppKit

/// Manages security-scoped bookmarks for the two CLI data folders.
///
/// Because the app is sandboxed (App Store-ready), it cannot read `~/.claude`
/// or `~/.codex` directly. The user grants each folder once via an open panel;
/// we persist an app-scoped security-scoped bookmark and resolve it on launch.
final class FolderAccess {

    enum Slot: String, CaseIterable {
        case claude, codex
        var defaultPath: String { self == .claude ? "~/.claude" : "~/.codex" }
        var displayName: String { self == .claude ? "Claude (~/.claude)" : "Codex (~/.codex)" }
    }

    private let defaults = UserDefaults.standard
    private func key(_ slot: Slot) -> String { "bookmark.\(slot.rawValue)" }

    var hasAllAccess: Bool { Slot.allCases.allSatisfy { defaults.data(forKey: key($0)) != nil } }

    func hasAccess(_ slot: Slot) -> Bool { defaults.data(forKey: key(slot)) != nil }

    /// Present an open panel to grant access to a folder, defaulting to its CLI path.
    @MainActor
    func requestAccess(_ slot: Slot) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "授权 AI Buddies 读取 \(slot.displayName) 目录（只读）"
        panel.prompt = "授权"
        let expanded = (slot.defaultPath as NSString).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: expanded)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: key(slot))
            return true
        } catch {
            NSLog("Bookmark creation failed for \(slot): \(error)")
            return false
        }
    }

    /// Resolve a slot's bookmark to a URL (does not start access).
    func resolvedURL(_ slot: Slot) -> URL? {
        guard let data = defaults.data(forKey: key(slot)) else { return nil }
        var stale = false
        let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale, let url {
            // Refresh the stale bookmark.
            if let fresh = try? url.bookmarkData(options: [.withSecurityScope]) {
                defaults.set(fresh, forKey: key(slot))
            }
        }
        return url
    }

    /// Run `body` with both folders' security scope active, then balance the access.
    /// Returns resolved scan directories: (claudeDirs, codexDir).
    func withAccess<T>(_ body: (_ claudeDirs: [String], _ codexDir: String?) -> T) -> T {
        var started: [URL] = []
        defer { started.forEach { $0.stopAccessingSecurityScopedResource() } }

        var claudeDirs: [String] = []
        var codexDir: String?

        if let url = resolvedURL(.claude), url.startAccessingSecurityScopedResource() {
            started.append(url)
            claudeDirs.append(url.appendingPathComponent(AppConstants.claudeProjectsSubpath).path)
        }
        if let url = resolvedURL(.codex), url.startAccessingSecurityScopedResource() {
            started.append(url)
            codexDir = url.appendingPathComponent(AppConstants.codexSessionsSubpath).path
        }
        return body(claudeDirs, codexDir)
    }

    func clear() { Slot.allCases.forEach { defaults.removeObject(forKey: key($0)) } }
}
