import SwiftUI

@main
struct AIBuddiesApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
                .frame(width: 340)
        } label: {
            MenuBarLabelView()
                .environmentObject(model)
                .task { model.start() }
        }
        .menuBarExtraStyle(.window)

        Window("AI Buddies", id: WindowID.dashboard) {
            DashboardRootView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 580)
                .preferredColorScheme(model.settings.appearance.colorScheme)
                .task { model.start() }
        }
        .defaultSize(width: 980, height: 680)
    }
}

enum WindowID {
    static let dashboard = "dashboard"
}
