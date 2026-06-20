import SwiftUI
import UsageCore

/// Claude / Codex detail pane (spec §5.2).
struct ProviderDetailView: View {
    @EnvironmentObject var model: AppModel
    let provider: Provider

    var body: some View {
        ScrollView {
            if let s = model.snapshot {
                VStack(alignment: .leading, spacing: 18) {
                    rings(s)
                    summary(s)
                    tokenBreakdown(s)
                    sessions(s)
                }
                .padding(20)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .navigationTitle(provider.displayName)
    }

    private func rings(_ s: Snapshot) -> some View {
        let five = model.window(provider, .fiveHour, in: s)
        let weekly = model.window(provider, .weekly, in: s)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(text: "额度窗口")
                    if let five { SourceBadge(isEstimated: five.isEstimated) }
                }
                HStack(spacing: 40) {
                    bigRing(five, title: "5 小时")
                    bigRing(weekly, title: "每周")
                }
                if provider == .claude {
                    Text("注：Claude 官方剩余额度% 仅在 HTTP header，本地不可得，此处为窗口用量估算代理。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func bigRing(_ w: WindowState?, title: String) -> some View {
        VStack(spacing: 6) {
            RingView(percent: w?.usedPercent, color: w?.status.color ?? .gray, lineWidth: 12,
                     caption: w.map { $0.isEstimated ? "已用(估)" : "已用" } ?? nil)
                .frame(width: 110, height: 110)
            Text(title).font(.callout)
            if let w, !w.isEstimated, let reset = w.resetsAt {
                Text("约 \(Formatting.humanDuration(reset.timeIntervalSinceNow))后重置")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func summary(_ s: Snapshot) -> some View {
        Card {
            HStack(spacing: 24) {
                if provider == .claude {
                    metric("等效费用", Formatting.usd(s.claude.equivCostUSD))
                    metric("调用数", "\(s.claude.calls)")
                    metric("近7天(估)", Formatting.usd(s.claude.window7dEstimate.equivCostUSD))
                } else {
                    metric("等效费用≈", Formatting.usd(s.codex.equivCostUSDApprox))
                    metric("会话数", "\(s.codex.sessions)")
                    if s.subagentSuspect > 0 {
                        metric("疑似子代理", "\(s.subagentSuspect)")
                    }
                }
            }
        }
    }

    private func tokenBreakdown(_ s: Snapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Token 明细")
                if provider == .claude {
                    tokenRow("输入", s.claude.inputTokens)
                    tokenRow("输出", s.claude.outputTokens)
                    tokenRow("缓存读取", s.claude.cacheReadTokens)
                    tokenRow("缓存写入", s.claude.cacheWriteTokens)
                } else {
                    tokenRow("输入", s.codex.inputTokens)
                    tokenRow("输出", s.codex.outputTokens)
                    tokenRow("缓存", s.codex.cacheReadTokens)
                    if s.codex.priceIsApprox {
                        Text("Codex 价格为近似值，等效费用仅供参考。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func sessions(_ s: Snapshot) -> some View {
        let items = s.byProjectTop.filter { $0.provider == provider }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: provider == .claude ? "最近项目" : "最近会话")
                if items.isEmpty {
                    Text("暂无").foregroundStyle(.secondary)
                } else {
                    let maxCost = items.map(\.equivCostUSD).max() ?? 1
                    ForEach(items, id: \.name) { p in
                        BarRow(label: p.name, valueText: Formatting.usd(p.equivCostUSD),
                               fraction: p.equivCostUSD / maxCost,
                               color: Theme.providerColor(provider))
                    }
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
    private func tokenRow(_ label: String, _ value: Int) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer()
            Text(value.formatted(.number)).monospacedDigit() }
    }
}
