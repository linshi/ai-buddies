import SwiftUI
import Charts
import UsageCore

/// iOS trends screen (spec §5.3): 7-day stacked bars + daily list.
struct TrendsView: View {
    @EnvironmentObject var model: IOSModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = model.snapshot {
                    let days = Array(s.byDay.suffix(7))
                    VStack(alignment: .leading, spacing: 16) {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionTitle(text: "近 7 天等效费用")
                                if days.isEmpty {
                                    Text("暂无数据").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 140)
                                } else {
                                    Chart {
                                        ForEach(days, id: \.day) { d in
                                            BarMark(x: .value("日期", shortDay(d.day)), y: .value("Claude", d.claudeCostUSD))
                                                .foregroundStyle(Theme.claude)
                                            BarMark(x: .value("日期", shortDay(d.day)), y: .value("Codex", d.codexCostUSD))
                                                .foregroundStyle(Theme.codex)
                                        }
                                    }
                                    .chartForegroundStyleScale(["Claude": Theme.claude, "Codex": Theme.codex])
                                    .frame(height: 200)
                                }
                            }
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionTitle(text: "每日明细")
                                ForEach(days.reversed(), id: \.day) { d in
                                    HStack {
                                        Text(d.day).font(.callout).monospacedDigit()
                                        Spacer()
                                        Text(Formatting.usd(d.equivCostUSD)).monospacedDigit()
                                    }
                                    if d.day != days.first?.day { Divider() }
                                }
                            }
                        }
                    }
                    .padding()
                } else {
                    EmptyStateView(message: model.lastError).padding(.top, 80)
                }
            }
            .navigationTitle("趋势")
            .refreshable { await model.refresh() }
        }
    }

    private func shortDay(_ s: String) -> String {
        // "2026-06-19" → "06-19"
        s.count >= 10 ? String(s.dropFirst(5)) : s
    }
}
