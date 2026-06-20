import WidgetKit
import SwiftUI
import UsageCore

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

struct UsageProvider: TimelineProvider {
    private var isDemo: Bool { ProcessInfo.processInfo.environment["AIBUDDIES_DEMO"] == "1" }

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snap = isDemo ? .sample() : (SnapshotStore.load() ?? .sample())
        completion(UsageEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let snap = isDemo ? Snapshot.sample() : SnapshotStore.load()
        let entry = UsageEntry(date: Date(), snapshot: snap)
        // Refresh roughly every 20 minutes (system widget budget; spec §8).
        let next = Date().addingTimeInterval(20 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Helpers

private func window(_ snapshot: Snapshot?, _ provider: Provider, _ kind: WindowKind) -> WindowState? {
    snapshot?.windows.first { $0.provider == provider && $0.kind == kind }
}

private func todayCost(_ snapshot: Snapshot?) -> Double {
    guard let snapshot else { return 0 }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    let key = f.string(from: Date())
    return snapshot.byDay.first { $0.day == key }?.equivCostUSD ?? 0
}

// MARK: - Small (single provider, dual ring)

struct SmallWidgetView: View {
    let entry: UsageEntry
    private let provider: Provider = .codex   // spec §5.4 default

    var body: some View {
        let five = window(entry.snapshot, provider, .fiveHour)
        let weekly = window(entry.snapshot, provider, .weekly)
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle().fill(Theme.providerColor(provider)).frame(width: 7, height: 7)
                Text(provider.displayName).font(.caption).bold()
                Spacer()
            }
            HStack(spacing: 10) {
                WidgetRing(percent: five?.usedPercent, color: five?.status.color ?? .gray, label: "5h")
                WidgetRing(percent: weekly?.usedPercent, color: weekly?.status.color ?? .gray, label: "周")
            }
        }
        .padding()
    }
}

// MARK: - Medium (two providers + today $ + 1 tip)

struct MediumWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("今日 " + Formatting.usd(todayCost(entry.snapshot)))
                    .font(.headline).monospacedDigit()
                Spacer()
            }
            providerBar(.claude)
            providerBar(.codex)
            if let tip = entry.snapshot?.tips.min(by: { $0.severity.rank < $1.severity.rank }) {
                HStack(spacing: 4) {
                    Image(systemName: tip.severity.systemImage).foregroundStyle(tip.severity.color)
                    Text(tip.text).font(.caption2).lineLimit(2)
                }
            }
        }
        .padding()
    }

    private func providerBar(_ p: Provider) -> some View {
        let w = window(entry.snapshot, p, .fiveHour)
        let pct = w?.usedPercent ?? 0
        return HStack(spacing: 6) {
            Text(p.shortLabel).font(.caption2).bold().frame(width: 12)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill((w?.status.color ?? .gray).opacity(0.2))
                    Capsule().fill(w?.status.color ?? .gray)
                        .frame(width: max(3, geo.size.width * pct / 100))
                }
            }
            .frame(height: 8)
            Text(w?.usedPercent.map { "\(Int($0))%" } ?? "—").font(.caption2).monospacedDigit().frame(width: 34)
        }
    }
}

// MARK: - Lock screen circular

struct CircularWidgetView: View {
    let entry: UsageEntry
    var body: some View {
        let w = window(entry.snapshot, .codex, .fiveHour)
        Gauge(value: (w?.usedPercent ?? 0) / 100) {
            Text("X")
        } currentValueLabel: {
            Text(w?.usedPercent.map { "\(Int($0))" } ?? "—").font(.caption2)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

struct WidgetRing: View {
    let percent: Double?
    let color: Color
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 6)
                Circle().trim(from: 0, to: CGFloat(min(max((percent ?? 0) / 100, 0), 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(percent.map { "\(Int($0))" } ?? "—").font(.system(.caption2, design: .rounded)).bold()
            }
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Widget configuration

struct UsageWidget: Widget {
    let kind = "AIBuddiesUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AI Buddies 用量")
        .description("一眼看清 Claude / Codex 额度与今日等效费用。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: UsageEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallWidgetView(entry: entry)
        case .systemMedium: MediumWidgetView(entry: entry)
        case .accessoryCircular: CircularWidgetView(entry: entry)
        default: SmallWidgetView(entry: entry)
        }
    }
}

@main
struct AIBuddiesWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}
