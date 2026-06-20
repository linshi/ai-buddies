import SwiftUI
import UsageCore

/// iOS tips screen (spec §5.3): all tip cards.
struct IOSTipsView: View {
    @EnvironmentObject var model: IOSModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = model.snapshot {
                    let tips = s.tips.sorted { $0.severity.rank < $1.severity.rank }
                    VStack(spacing: 12) {
                        ForEach(tips) { tip in
                            Card { TipRow(tip: tip) }
                        }
                    }
                    .padding()
                } else {
                    EmptyStateView(message: model.lastError).padding(.top, 80)
                }
            }
            .navigationTitle("建议")
            .refreshable { await model.refresh() }
        }
    }
}
