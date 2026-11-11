import WidgetKit
import SwiftUI
import ClockHandKit

// M0 spike: does the private clock-hand rotation effect spin a record on this
// iPhone, for an app built by our CI's Xcode? No Spotify yet — just the spin.

struct SpinTestEntry: TimelineEntry {
    let date: Date
}

struct SpinTestProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpinTestEntry {
        SpinTestEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SpinTestEntry) -> Void) {
        completion(SpinTestEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpinTestEntry>) -> Void) {
        SharedStore.recordHeartbeat(family: String(describing: context.family))
        // One entry is enough: the rotation is driven by the system clock, not by entries.
        // The 30-minute reload only exists to log heartbeats for Diagnostics.
        let timeline = Timeline(
            entries: [SpinTestEntry(date: Date())],
            policy: .after(Date().addingTimeInterval(30 * 60))
        )
        completion(timeline)
    }
}

struct SpinTestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpinTest", provider: SpinTestProvider()) { _ in
            SpinTestView()
        }
        .configurationDisplayName("Spin test")
        .description("Checks whether the vinyl can spin on this iPhone.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// A record that rotates once every `secondsPerTurn`, with a static sheen on top.
struct SpinningRecord: View {
    let secondsPerTurn: Double

    var body: some View {
        ZStack {
            VinylDisc()
                .clockHandRotationEffect(period: .custom(secondsPerTurn))
            VinylSheen()
        }
    }
}

struct SpinTestView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                Color(red: 0.06, green: 0.06, blue: 0.07)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            // Both candidate speeds side by side, to judge which looks natural.
            HStack(spacing: 18) {
                labelled(SpinningRecord(secondsPerTurn: 3.6), "16⅔ RPM")
                labelled(SpinningRecord(secondsPerTurn: 1.8), "33⅓ RPM")
            }
        default:
            SpinningRecord(secondsPerTurn: 3.6)
                .padding(4)
        }
    }

    private func labelled(_ record: SpinningRecord, _ caption: String) -> some View {
        VStack(spacing: 6) {
            record
            Text(caption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
