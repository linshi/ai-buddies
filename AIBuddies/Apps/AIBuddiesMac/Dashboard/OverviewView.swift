import SwiftUI
import Charts
import UsageCore

/// Overview pane: KPIs, daily stacked cost chart, by-model & top-project bars, top tips.
struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    var jump: (DashboardSection) -> Void
    @State private var rangeDays = 7

    var body: some View {
        ScrollView {
            if let snapshot = model.snapshot {
                VStack(alignment: .leading, spacing: 18) {
                    kpis(snapshot)
                    dailyChart(snapshot)
                    HStack(alignment: .top, spacing: 16) {
                        byModel(snapshot)
                        topProjects(snapshot)
                    }
                    tips(snapshot)
                }
                .padding(20)
            } else {
                ProgressView("读取中…").frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .navigationTitle("概览")
    }

    // MARK: KPIs

    private func kpis(_ s: Snapshot) -> some View {
        let weekly = s.claude.window7dEstimate.equivCostUSD + recentCodexCost(s, days: 7)
        let claude5h = model.window(.claude, .fiveHour, in: s)
        let codexWeek = model.window(.codex, .weekly, in: s)
        let weekTokens = s.byDay.suffix(7).reduce(0) { $0 + $1.tokens }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            KPICard(title: "本周等效 $", value: Formatting.usd(weekly), sub: "Claude+Codex", tint: .accentColor) { jump(.tips) }
            KPICard(title: "Claude 5h 剩余", value: pctRemaining(claude5h), sub: "估算", tint: (claude5h?.status.color ?? .gray)) { jump(.claude) }
            KPICard(title: "Codex 每周剩余", value: pctRemaining(codexWeek), sub: "权威", tint: (codexWeek?.status.color ?? .gray)) { jump(.codex) }
            KPICard(title: "本周 token", value: compact(weekTokens), sub: nil) { jump(.models) }
        }
    }

    // MARK: Daily chart

    private func dailyChart(_ s: Snapshot) -> some View {
        let days = Array(s.byDay.suffix(rangeDays))
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionTitle(text: "每日等效费用")
                    Spacer()
                    Picker("", selection: $rangeDays) {
                        Text("7").tag(7); Text("14").tag(14); Text("30").tag(30)
                    }
                    .pickerStyle(.segmented).frame(width: 150)
                }
                if days.isEmpty {
                    Text("暂无数据").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    Chart {
                        ForEach(days, id: \.day) { d in
                            BarMark(x: .value("日期", d.day), y: .value("Claude", d.claudeCostUSD))
                                .foregroundStyle(Theme.claude)
                            BarMark(x: .value("日期", d.day), y: .value("Codex", d.codexCostUSD))
                                .foregroundStyle(Theme.codex)
                        }
                    }
                    .chartForegroundStyleScale(["Claude": Theme.claude, "Codex": Theme.codex])
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
                    .frame(height: 200)
                }
            }
        }
    }

    // MARK: Bars

    private func byModel(_ s: Snapshot) -> some View {
        let top = Array(s.byModel.prefix(6))
        let maxCost = top.map(\.equivCostUSD).max() ?? 1
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "按模型")
                ForEach(top, id: \.name) { m in
                    BarRow(label: m.name, valueText: Formatting.usd(m.equivCostUSD),
                           fraction: m.equivCostUSD / maxCost,
                           color: m.name.hasPrefix("codex") ? Theme.codex : Theme.claude)
                }
            }
        }
    }

    private func topProjects(_ s: Snapshot) -> some View {
        let top = Array(s.byProjectTop.prefix(6))
        let maxCost = top.map(\.equivCostUSD).max() ?? 1
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Top 项目")
                ForEach(top, id: \.name) { p in
                    BarRow(label: p.name, valueText: Formatting.usd(p.equivCostUSD),
                           fraction: p.equivCostUSD / maxCost,
                           color: (p.provider == .codex) ? Theme.codex : Theme.claude) { jump(.projects) }
                }
            }
        }
    }

    private func tips(_ s: Snapshot) -> some View {
        let top = s.tips.sorted { $0.severity.rank < $1.severity.rank }.prefix(4)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack { SectionTitle(text: "建议"); Spacer()
                    Button("全部") { jump(.tips) }.buttonStyle(.link) }
                ForEach(Array(top)) { TipRow(tip: $0) }
            }
        }
    }

    // MARK: Helpers

    private func pctRemaining(_ w: WindowState?) -> String {
        guard let p = w?.usedPercent else { return "—" }
        return "\(Int(max(0, 100 - p)))%"
    }
    private func recentCodexCost(_ s: Snapshot, days: Int) -> Double {
        s.byDay.suffix(days).reduce(0) { $0 + $1.codexCostUSD }
    }
    private func compact(_ n: Int) -> String {
        if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1e9) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1e6) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1e3) }
        return "\(n)"
    }
}
