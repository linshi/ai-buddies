import SwiftUI
import UsageCore

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview, claude, codex, projects, models, tips, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .projects: return "项目"
        case .models: return "模型"
        case .tips: return "建议"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .claude: return "brain.head.profile"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .projects: return "folder"
        case .models: return "cpu"
        case .tips: return "lightbulb"
        case .settings: return "gearshape"
        }
    }
}

/// macOS dashboard window: 7-item sidebar + detail (spec §5.2).
struct DashboardRootView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: DashboardSection = .overview

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            Group {
                if model.needsFolderAccess {
                    VStack { OnboardingView().frame(maxWidth: 460) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    detail(for: selection)
                }
            }
            .toolbar { toolbar }
        }
        .preferredColorScheme(model.settings.appearance.colorScheme)
    }

    @ViewBuilder
    private func detail(for section: DashboardSection) -> some View {
        switch section {
        case .overview: OverviewView(jump: { selection = $0 })
        case .claude:   ProviderDetailView(provider: .claude)
        case .codex:    ProviderDetailView(provider: .codex)
        case .projects: ProjectsView()
        case .models:   ModelsView()
        case .tips:     TipsView()
        case .settings: SettingsView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            if let last = model.lastRefresh {
                Text("更新于 \(last, style: .time)").font(.caption).foregroundStyle(.secondary)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)
        }
    }
}
