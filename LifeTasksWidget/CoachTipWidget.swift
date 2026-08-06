import WidgetKit
import SwiftUI

// MARK: - Coach Tip Widget

/// "Do this next", on the home or lock screen.
///
/// Read-only by design. Every other coach surface can act — a proposal button, a
/// builder, a Retry — and none of that belongs here: a widget tap that mutated
/// data would be the one path from model output to a change without a
/// confirmation in front of it. This shows what the coach said and opens the app.
struct CoachTipProvider: TimelineProvider {

    func placeholder(in context: Context) -> CoachTipEntry {
        CoachTipEntry(date: Date(), tip: SharedCoachTip(
            headline: "A short walk after lunch",
            summary: "You're a few thousand steps behind your usual by this time.",
            origin: "onDevice",
            generatedAt: Date()
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (CoachTipEntry) -> Void) {
        let tip = SharedCoachTipStore.read()
        completion(CoachTipEntry(date: Date(), tip: tip ?? placeholder(in: context).tip))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CoachTipEntry>) -> Void) {
        let entry = CoachTipEntry(date: Date(), tip: SharedCoachTipStore.read())
        // Half-hourly. The tip changes when the underlying figures do, and the
        // app reloads timelines when it writes one — this is only the backstop
        // that lets a tip age out of the store on its own.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct CoachTipEntry: TimelineEntry {
    let date: Date
    /// Nil when there is no current tip. Rendered as an invitation, never as an
    /// error and never as an empty box pretending to hold something.
    let tip: SharedCoachTip?
}

struct CoachTipWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CoachTipEntry

    var body: some View {
        if let tip = entry.tip {
            VStack(alignment: .leading, spacing: 6) {
                Label(tip.originLabel, systemImage: tip.originIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(tip.headline)
                    .font(family == .systemSmall ? .subheadline.weight(.semibold) : .headline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(family == .systemSmall ? 3 : 2)

                if family != .systemSmall {
                    Text(tip.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(tip.originLabel). \(tip.headline). \(tip.summary)")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("No suggestion yet")
                    .font(.subheadline.weight(.semibold))
                Text("Open Life to get today's.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

struct LifeCoachWidget: Widget {
    let kind = "LifeCoachWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CoachTipProvider()) { entry in
            CoachTipWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "life://coach"))
        }
        .configurationDisplayName("Coach")
        .description("What the coach suggests doing next, and who wrote it.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
