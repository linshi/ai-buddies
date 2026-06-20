import SwiftUI
import UsageCore

/// Circular quota gauge. `percent` is 0–100; nil renders an empty/unknown ring.
struct RingView: View {
    let percent: Double?
    let color: Color
    var lineWidth: CGFloat = 10
    var caption: String?

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max((percent ?? 0) / 100, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: percent)
            VStack(spacing: 1) {
                Text(percent.map { "\(Int($0))%" } ?? "—")
                    .font(.system(.title3, design: .rounded)).bold()
                    .monospacedDigit()
                if let caption {
                    Text(caption).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A small labeled badge: "权威" / "估算".
struct SourceBadge: View {
    let isEstimated: Bool
    var body: some View {
        Text(isEstimated ? "估算" : "权威")
            .font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((isEstimated ? Color.orange : Color.green).opacity(0.18), in: Capsule())
            .foregroundStyle(isEstimated ? Color.orange : Color.green)
    }
}

/// Card container.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 0.5))
    }
}

/// A KPI tile for the overview grid.
struct KPICard: View {
    let title: String
    let value: String
    var sub: String?
    var tint: Color = .primary
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.system(.title2, design: .rounded)).bold().foregroundStyle(tint)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    if let sub { Text(sub).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

/// A coaching tip row.
struct TipRow: View {
    let tip: Tip
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: tip.severity.systemImage)
                .foregroundStyle(tip.severity.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.category).font(.caption).bold().foregroundStyle(tip.severity.color)
                Text(tip.text).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A labeled horizontal magnitude bar (for by-model / by-project lists).
struct BarRow: View {
    let label: String
    let valueText: String
    let fraction: Double   // 0–1
    var color: Color = .accentColor
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label).font(.callout).lineLimit(1)
                    Spacer()
                    Text(valueText).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(color.opacity(0.15))
                        Capsule().fill(color)
                            .frame(width: max(2, geo.size.width * min(max(fraction, 0), 1)))
                    }
                }
                .frame(height: 7)
            }
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

/// Section header used in detail panes.
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.headline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
