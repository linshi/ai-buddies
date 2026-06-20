import SwiftUI
import UsageCore

/// The dropdown panel under the menu bar item (spec §5.1).
struct MenuBarContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.needsFolderAccess {
                OnboardingView()
            } else if let snapshot = model.snapshot {
                content(snapshot)
            } else {
                ProgressView("读取中…").frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .padding(12)
    }

    @ViewBuilder
    private func content(_ snapshot: Snapshot) -> some View {
        ProviderQuickCard(
            provider: .claude,
            five: model.window(.claude, .fiveHour, in: snapshot),
            weekly: model.window(.claude, .weekly, in: snapshot),
            todayUSD: nil,
            costUSD: snapshot.claude.equivCostUSD
        )
        .onTapGesture { open(.claude) }

        ProviderQuickCard(
            provider: .codex,
            five: model.window(.codex, .fiveHour, in: snapshot),
            weekly: model.window(.codex, .weekly, in: snapshot),
            todayUSD: nil,
            costUSD: snapshot.codex.equivCostUSDApprox
        )
        .onTapGesture { open(.codex) }

        if let tip = topTip(snapshot) {
            Divider()
            TipRow(tip: tip)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await model.refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)

            Spacer()

            if let last = model.lastRefresh {
                Text(last, style: .time).font(.caption2).foregroundStyle(.secondary)
            }

            Button {
                openWindow(id: WindowID.dashboard)
            } label: {
                Label("仪表盘", systemImage: "rectangle.on.rectangle")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
        }
        .buttonStyle(.borderless)
    }

    private func open(_ provider: Provider) {
        openWindow(id: WindowID.dashboard)
    }

    /// Highest-severity tip (spec §5.1 "most important one").
    private func topTip(_ snapshot: Snapshot) -> Tip? {
        snapshot.tips.min { $0.severity.rank < $1.severity.rank }
    }
}

/// Compact two-ring provider card for the menu dropdown.
struct ProviderQuickCard: View {
    let provider: Provider
    let five: WindowState?
    let weekly: WindowState?
    let todayUSD: Double?
    let costUSD: Double

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(Theme.providerColor(provider)).frame(width: 8, height: 8)
                    Text(provider.displayName).font(.headline)
                    if let five { SourceBadge(isEstimated: five.isEstimated) }
                    Spacer()
                    Text(Formatting.usd(costUSD)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    ring(five, fallbackLabel: "5h")
                    ring(weekly, fallbackLabel: "周")
                }
            }
        }
    }

    @ViewBuilder
    private func ring(_ window: WindowState?, fallbackLabel: String) -> some View {
        VStack(spacing: 4) {
            RingView(percent: window?.usedPercent, color: window?.status.color ?? .gray, lineWidth: 7)
                .frame(width: 54, height: 54)
            Text(window?.kind.displayName ?? fallbackLabel).font(.caption2).foregroundStyle(.secondary)
            if let reset = window?.resetsAt, !(window?.isEstimated ?? true) {
                Text(Formatting.humanDuration(reset.timeIntervalSinceNow))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
