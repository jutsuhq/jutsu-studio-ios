import SwiftUI
import WidgetKit

/// Home Screen and Lock Screen: what is running, what is ready, and today's spend.
struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JutsuStatus", provider: StatusProvider()) { entry in
            StatusView(snapshot: entry.snapshot)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Jutsu")
        .description("Takes rendering, takes ready and today's spend.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, snapshot: WidgetSnapshot(running: 2, ready: 3, spentToday: "48 cr", updatedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now, snapshot: WidgetSnapshot.read().asOf(.now)))
    }

    /// A second entry at midnight clears today's counts even if the app doesn't write again.
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let snapshot = WidgetSnapshot.read()
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .distantFuture
        let entries = [Date.now, midnight].map { StatusEntry(date: $0, snapshot: snapshot.asOf($0)) }
        completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

private struct StatusView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading) {
                Text("Jutsu").font(.headline)
                Text("\(snapshot.running) rendering · \(snapshot.ready) ready")
                Text(snapshot.spentToday).font(.system(.caption, design: .monospaced))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(Color(red: 0.851, green: 0.275, blue: 0.937))
                    .accessibilityHidden(true)
                Spacer()
                Text("\(snapshot.running)").font(.system(size: 40, weight: .heavy, design: .rounded))
                Text("rendering").font(.caption).foregroundStyle(.secondary)
                Text("\(snapshot.ready) ready · \(snapshot.spentToday)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(red: 0.831, green: 1, blue: 0.165))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
