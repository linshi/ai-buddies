import SwiftUI
import UsageCore

/// Shared visual language for both apps and the widgets.
public enum Theme {
    /// Brand accents per provider (prototype: Claude terracotta, Codex teal).
    public static let claude = Color(red: 0.80, green: 0.42, blue: 0.27)
    public static let codex = Color(red: 0.18, green: 0.55, blue: 0.55)

    public static func providerColor(_ p: Provider) -> Color {
        p == .claude ? claude : codex
    }
}

public extension WindowState.Status {
    /// Color encoding per spec §6.2 (<70 green / 70–90 amber / ≥90 red).
    var color: Color {
        switch self {
        case .green: return Color(red: 0.20, green: 0.70, blue: 0.40)
        case .amber: return Color(red: 0.95, green: 0.62, blue: 0.10)
        case .red: return Color(red: 0.90, green: 0.26, blue: 0.21)
        case .unknown: return .gray
        }
    }
}

public extension Tip.Severity {
    var color: Color {
        switch self {
        case .danger: return Color(red: 0.90, green: 0.26, blue: 0.21)
        case .warn: return Color(red: 0.95, green: 0.62, blue: 0.10)
        case .info: return Color(red: 0.25, green: 0.50, blue: 0.85)
        case .success: return Color(red: 0.20, green: 0.70, blue: 0.40)
        }
    }

    var systemImage: String {
        switch self {
        case .danger: return "exclamationmark.octagon.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.seal.fill"
        }
    }
}

public extension Provider {
    var displayName: String { self == .claude ? "Claude" : "Codex" }
    var shortLabel: String { self == .claude ? "C" : "X" }
}

public extension WindowKind {
    var displayName: String {
        switch self {
        case .fiveHour: return "5 小时"
        case .weekly: return "每周"
        case .weeklySonnet: return "每周 (Sonnet)"
        }
    }
}

extension SettingsStore.Appearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
