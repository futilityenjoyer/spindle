import WidgetKit
import SwiftUI
import ClockHandKit
import Core

// M1 widget: shows what Spotify is playing and spins only while it plays.
// Album art arrives in M2; the queue-predicting timeline and buttons in M4.
// The kind stays "SpinTest" so widgets already on the Home Screen keep working.

/// What the widget shows, derived from a playback snapshot or a failure.
enum WidgetPlayback {
    case notConnected
    case waitingForUnlock
    case nothingPlaying
    case playing(PlayableItem, isPlaying: Bool)
    case advertisement(isPlaying: Bool)
    case problem(String)

    init(_ snapshot: PlaybackSnapshot) {
        guard let now = snapshot.nowPlaying else { self = .nothingPlaying; return }
        if let item = now.item {
            self = .playing(item, isPlaying: now.isPlaying)
        } else if now.kind == .ad {
            self = .advertisement(isPlaying: now.isPlaying)
        } else {
            self = .nothingPlaying
        }
    }

    var isPlaying: Bool {
        switch self {
        case .playing(_, let isPlaying), .advertisement(let isPlaying): return isPlaying
        default: return false
        }
    }

    var title: String {
        switch self {
        case .notConnected: return "Connect Spotify"
        case .waitingForUnlock: return "Unlock to update"
        case .nothingPlaying: return "Nothing playing"
        case .playing(let item, _): return item.title
        case .advertisement: return "Advertisement"
        case .problem: return "Can't reach Spotify"
        }
    }

    var subtitle: String {
        switch self {
        case .notConnected: return "Open Spindle to sign in"
        case .playing(let item, _): return item.subtitle
        case .problem(let message): return message
        default: return ""
        }
    }

    /// How long until iOS should ask for a new timeline. Simple for M1; the
    /// queue-predicting planner (FEASIBILITY §4.7) replaces this in M4.
    var nextReload: TimelineReloadPolicy {
        switch self {
        case .notConnected: return .never   // the app reloads the widget after sign-in
        case .waitingForUnlock: return .after(Date().addingTimeInterval(15 * 60))
        case .playing, .advertisement: return .after(Date().addingTimeInterval(isPlaying ? 10 * 60 : 30 * 60))
        case .nothingPlaying: return .after(Date().addingTimeInterval(60 * 60))
        case .problem: return .after(Date().addingTimeInterval(30 * 60))
        }
    }

    /// Reuse the app's (or another widget's) fetch if it's under a minute old;
    /// otherwise make one request burst to Spotify.
    static func load() async -> WidgetPlayback {
        if let snapshot = SharedStore.loadSnapshot(), snapshot.isFresh(now: Date()) {
            return WidgetPlayback(snapshot)
        }
        do {
            return WidgetPlayback(try await SpotifyService.fetchPlayback())
        } catch SpotifyService.Failure.notSignedIn {
            return .notConnected
        } catch SpotifyService.Failure.api(.invalidGrant) {
            return .notConnected
        } catch SpotifyService.Failure.waitingForUnlock {
            return .waitingForUnlock
        } catch SpotifyService.Failure.network {
            return .problem("Offline")
        } catch SpotifyService.Failure.api(.forbidden) {
            return .problem("Access refused — open Spindle")
        } catch {
            return .problem("Open Spindle for details")
        }
    }
}

struct SpindleEntry: TimelineEntry {
    let date: Date
    let playback: WidgetPlayback
}

struct SpindleProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpindleEntry {
        SpindleEntry(date: Date(), playback: .nothingPlaying)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpindleEntry) -> Void) {
        // Gallery preview: show the last known state without touching the network.
        let playback = SharedStore.loadSnapshot().map(WidgetPlayback.init) ?? .nothingPlaying
        completion(SpindleEntry(date: Date(), playback: playback))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpindleEntry>) -> Void) {
        SharedStore.recordHeartbeat(family: String(describing: context.family))
        Task {
            let playback = await WidgetPlayback.load()
            let entry = SpindleEntry(date: Date(), playback: playback)
            completion(Timeline(entries: [entry], policy: playback.nextReload))
        }
    }
}

struct SpinTestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpinTest", provider: SpindleProvider()) { entry in
            SpindleWidgetView(entry: entry)
        }
        .configurationDisplayName("Spindle")
        .description("A spinning record for what's playing on Spotify.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// A record that turns at 16⅔ RPM while `spinning`, under a static sheen.
struct RecordView: View {
    let spinning: Bool

    var body: some View {
        ZStack {
            disc
            VinylSheen()
        }
    }

    @ViewBuilder
    private var disc: some View {
        if spinning {
            VinylDisc().clockHandRotationEffect(period: .custom(3.6))
        } else {
            VinylDisc()
        }
    }
}

struct SpindleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: SpindleEntry

    private var spinning: Bool { entry.playback.isPlaying && !reduceMotion }

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
            HStack(spacing: 14) {
                RecordView(spinning: spinning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.playback.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if !entry.playback.subtitle.isEmpty {
                        Text(entry.playback.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    statusLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            RecordView(spinning: spinning)
                .padding(4)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 4) {
            if AppGroup.id == nil {
                Text("No shared folder")
            } else {
                Text(entry.playback.isPlaying ? "Playing ·" : "Updated")
                Text(entry.date, style: .time)
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.white.opacity(0.5))
    }
}
