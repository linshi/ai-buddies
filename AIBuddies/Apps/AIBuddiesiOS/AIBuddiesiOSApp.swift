import SwiftUI

@main
struct AIBuddiesiOSApp: App {
    @StateObject private var model = IOSModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
                .task { model.start() }
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject var model: IOSModel
    @State private var tab = Self.initialTab

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }.tag(0)
            TrendsView()
                .tabItem { Label("趋势", systemImage: "chart.bar.fill") }.tag(1)
            IOSTipsView()
                .tabItem { Label("建议", systemImage: "lightbulb.fill") }.tag(2)
            IOSSettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }.tag(3)
        }
    }

    /// Lets `--demo` screenshot runs open a specific tab via `AIBUDDIES_TAB`.
    private static var initialTab: Int {
        switch ProcessInfo.processInfo.environment["AIBUDDIES_TAB"] {
        case "trends": return 1
        case "tips": return 2
        case "settings": return 3
        default: return 0
        }
    }
}
