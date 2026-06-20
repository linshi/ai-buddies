import Foundation
import Combine

/// User settings (spec §8), persisted in UserDefaults.
final class SettingsStore: ObservableObject {

    enum ClaudePlan: String, CaseIterable, Identifiable {
        case pro = "Pro", max5 = "Max 5x", max20 = "Max 20x"
        var id: String { rawValue }
    }
    enum CodexPlan: String, CaseIterable, Identifiable {
        case plus = "Plus", pro = "Pro"
        var id: String { rawValue }
    }
    enum MenuBarDisplay: String, CaseIterable, Identifiable {
        case percent, dollars
        var id: String { rawValue }
        var label: String { self == .percent ? "额度 %" : "今日 $" }
    }
    enum RefreshInterval: Int, CaseIterable, Identifiable {
        case one = 1, five = 5, ten = 10
        var id: Int { rawValue }
        var seconds: TimeInterval { TimeInterval(rawValue * 60) }
        var label: String { "\(rawValue) 分钟" }
    }
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" }
        }
    }

    private let defaults = UserDefaults.standard

    @Published var claudePlan: ClaudePlan { didSet { defaults.set(claudePlan.rawValue, forKey: "claudePlan") } }
    @Published var codexPlan: CodexPlan { didSet { defaults.set(codexPlan.rawValue, forKey: "codexPlan") } }
    @Published var planPriceUSD: Double { didSet { defaults.set(planPriceUSD, forKey: "planPriceUSD") } }
    @Published var menuBarDisplay: MenuBarDisplay { didSet { defaults.set(menuBarDisplay.rawValue, forKey: "menuBarDisplay") } }
    @Published var refreshInterval: RefreshInterval { didSet { defaults.set(refreshInterval.rawValue, forKey: "refreshInterval") } }
    @Published var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    @Published var notificationThreshold: Double { didSet { defaults.set(notificationThreshold, forKey: "notificationThreshold") } }
    @Published var hashProjectNames: Bool { didSet { defaults.set(hashProjectNames, forKey: "hashProjectNames") } }
    /// iOS home screen default horizon (true = 今日, false = 本周).
    @Published var homeDefaultToday: Bool { didSet { defaults.set(homeDefaultToday, forKey: "homeDefaultToday") } }
    /// Opt-in: use the CloudKit public database to bridge two different iCloud
    /// accounts (e.g. a build Mac + a personal phone). Must be enabled on both ends.
    @Published var usePublicDatabase: Bool { didSet { defaults.set(usePublicDatabase, forKey: "usePublicDatabase") } }

    init() {
        claudePlan = ClaudePlan(rawValue: defaults.string(forKey: "claudePlan") ?? "") ?? .max5
        codexPlan = CodexPlan(rawValue: defaults.string(forKey: "codexPlan") ?? "") ?? .pro
        planPriceUSD = defaults.object(forKey: "planPriceUSD") as? Double ?? 200
        menuBarDisplay = MenuBarDisplay(rawValue: defaults.string(forKey: "menuBarDisplay") ?? "") ?? .percent
        refreshInterval = RefreshInterval(rawValue: defaults.integer(forKey: "refreshInterval")) ?? .five
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        notificationThreshold = defaults.object(forKey: "notificationThreshold") as? Double ?? 85
        hashProjectNames = defaults.bool(forKey: "hashProjectNames")
        homeDefaultToday = defaults.object(forKey: "homeDefaultToday") as? Bool ?? true
        usePublicDatabase = defaults.bool(forKey: "usePublicDatabase")
    }
}
