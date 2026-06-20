import SwiftUI
import UsageCore

/// iOS home screen (spec §5.3): 今日/本周 toggle, total $, provider cards, top tip.
struct HomeView: View {
    @EnvironmentObject var model: IOSModel
    @State private var today = true

    init() {}

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = model.snapshot {
                    VStack(spacing: 16) {
                        Picker("", selection: $today) {
                            Text("今日").tag(true)
                            Text("本周").tag(false)
                        }
                        .pickerStyle(.segmented)

                        Card {
                            VStack(spacing: 4) {
                                Text(today ? "今日等效合计" : "本周等效合计")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(Formatting.usd(model.cost(today: today)))
                                    .font(.system(.largeTitle, design: .rounded)).bold().monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                        }

                        ProviderCardiOS(provider: .claude,
                                        five: model.window(.claude, .fiveHour),
                                        weekly: model.window(.claude, .weekly),
                                        cost: s.claude.equivCostUSD)
                        ProviderCardiOS(provider: .codex,
                                        five: model.window(.codex, .fiveHour),
                                        weekly: model.window(.codex, .weekly),
                                        cost: s.codex.equivCostUSDApprox)

                        if let tip = model.topTip {
                            Card { TipRow(tip: tip) }
                        }
                    }
                    .padding()
                } else {
                    EmptyStateView(message: model.lastError)
                        .padding(.top, 80)
                }
            }
            .navigationTitle("AI Buddies")
            .toolbar { reloadButton }
            .refreshable { await model.refresh() }
        }
        .onAppear { today = model.settings.homeDefaultToday }
    }

    @ToolbarContentBuilder
    private var reloadButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(model.isLoading)
        }
    }
}

/// Provider summary card with dual rings (iOS).
struct ProviderCardiOS: View {
    let provider: Provider
    let five: WindowState?
    let weekly: WindowState?
    let cost: Double

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle().fill(Theme.providerColor(provider)).frame(width: 10, height: 10)
                    Text(provider.displayName).font(.headline)
                    if let five { SourceBadge(isEstimated: five.isEstimated) }
                    Spacer()
                    Text(Formatting.usd(cost)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack(spacing: 28) {
                    ring(five); ring(weekly)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func ring(_ w: WindowState?) -> some View {
        VStack(spacing: 6) {
            RingView(percent: w?.usedPercent, color: w?.status.color ?? .gray, lineWidth: 9)
                .frame(width: 72, height: 72)
            Text(w?.kind.displayName ?? "—").font(.caption).foregroundStyle(.secondary)
            if let w, !w.isEstimated, let reset = w.resetsAt {
                Text(Formatting.humanDuration(reset.timeIntervalSinceNow))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

struct EmptyStateView: View {
    let message: String?
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash").font(.largeTitle).foregroundStyle(.secondary)
            Text(message ?? "暂无数据，请下拉刷新。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }
}
