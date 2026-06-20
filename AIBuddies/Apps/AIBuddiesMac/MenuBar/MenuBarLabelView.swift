import SwiftUI
import UsageCore

/// The always-present menu bar status item (spec §5.1).
struct MenuBarLabelView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            if model.snapshot != nil {
                Text(model.menuBarTitle).monospacedDigit()
            } else {
                Text("AI")
            }
        }
        .task {
            // First run (no folder access yet) or demo: surface the dashboard window
            // automatically so onboarding/grant is reachable even if the menu bar
            // item is hidden by a menu-bar manager.
            if ProcessInfo.processInfo.environment["AIBUDDIES_DEMO"] == "1" || model.needsFolderAccess {
                openWindow(id: WindowID.dashboard)
            }
        }
    }

    private var iconName: String {
        switch model.menuBarStatus {
        case .red: return "exclamationmark.octagon.fill"
        case .amber: return "exclamationmark.triangle.fill"
        case .green, .unknown: return "gauge.with.dots.needle.50percent"
        }
    }
}
