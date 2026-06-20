import SwiftUI
import UsageCore

/// Models pane: token + equivalent $ by model, plus a saving hint (spec §5.2 模型).
struct ModelsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            if let s = model.snapshot {
                let items = s.byModel
                let maxCost = items.map(\.equivCostUSD).max() ?? 1
                VStack(alignment: .leading, spacing: 12) {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "按模型 · 等效费用")
                            ForEach(items, id: \.name) { m in
                                BarRow(label: m.name, valueText: "\(Formatting.usd(m.equivCostUSD)) · \(compact(m.tokens))",
                                       fraction: m.equivCostUSD / maxCost,
                                       color: m.name.hasPrefix("codex") ? Theme.codex : Theme.claude)
                            }
                        }
                    }
                    if let hint = savingHint(s) {
                        Card { TipRow(tip: hint) }
                    }
                }
                .padding(20)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .navigationTitle("模型")
    }

    private func savingHint(_ s: Snapshot) -> Tip? {
        // Surface the model-cost saving tip if present, else a generic nudge.
        s.tips.first { $0.category == "省钱" }
            ?? (s.byModel.contains { $0.name.contains("opus") }
                ? Tip(severity: .info, category: "省钱", text: "贵模型（Opus）适合复杂推理；日常小任务可切 Sonnet/Haiku 降本。")
                : nil)
    }

    private func compact(_ n: Int) -> String {
        if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1e9) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1e6) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1e3) }
        return "\(n) tok"
    }
}
