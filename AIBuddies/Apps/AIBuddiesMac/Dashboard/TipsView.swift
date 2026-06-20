import SwiftUI
import UsageCore

/// All tips with category labels (spec §5.2 建议).
struct TipsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            if let s = model.snapshot {
                let tips = s.tips.sorted { $0.severity.rank < $1.severity.rank }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tips) { tip in
                        Card { TipRow(tip: tip) }
                    }
                }
                .padding(20)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .navigationTitle("建议")
    }
}
