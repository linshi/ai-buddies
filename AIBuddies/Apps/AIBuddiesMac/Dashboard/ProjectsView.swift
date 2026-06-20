import SwiftUI
import UsageCore

/// Projects pane with drill-down (spec §5.2 项目).
struct ProjectsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: Snapshot.ProjectUsage?

    var body: some View {
        ScrollView {
            if let s = model.snapshot {
                let items = s.byProjectTop
                let maxCost = items.map(\.equivCostUSD).max() ?? 1
                VStack(alignment: .leading, spacing: 12) {
                    if let selected {
                        drilldown(selected)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "按等效费用排序")
                            ForEach(items, id: \.name) { p in
                                BarRow(label: p.name, valueText: Formatting.usd(p.equivCostUSD),
                                       fraction: p.equivCostUSD / maxCost,
                                       color: (p.provider == .codex) ? Theme.codex : Theme.claude) {
                                    selected = p
                                }
                            }
                        }
                    }
                }
                .padding(20)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .navigationTitle("项目")
    }

    private func drilldown(_ p: Snapshot.ProjectUsage) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button { selected = nil } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                    Text(p.name).font(.headline)
                    Spacer()
                    if let prov = p.provider {
                        Text(prov.displayName).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.providerColor(prov).opacity(0.18), in: Capsule())
                    }
                }
                HStack(spacing: 24) {
                    metric("等效费用", Formatting.usd(p.equivCostUSD))
                    metric("Token", p.tokens.formatted(.number))
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded)).bold().monospacedDigit()
        }
    }
}
