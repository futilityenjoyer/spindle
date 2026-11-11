import AppIntents
import WidgetKit
import SwiftUI
import ClockHandKit
import Core

// The Spindle widget. The kind stays "SpinTest" (its M0 name) so widgets already on
// the Home Screen keep working after updates.

/// What one timeline entry shows.
enum WidgetDisplay {
    case notConnected
    case waitingForUnlock
    case idle
    case item(PlayableItem, isPlaying: Bool, isStale: Bool)
    case advertisement(isPlaying: Bool)
    case problem(String)

    init(_ planned: PlannedEntry) {
        if planned.isAdvertisement {
            self = .advertisement(isPlaying: planned.isPlaying)
        } else if let item = planned.item {
            self = .item(item, isPlaying: planned.isPlaying, isStale: planned.isStale)
        } else {
            self = .idle
        }
    }

    var isPlaying: Bool {
        switch self {
        case .item(_, let isPlaying, _), .advertisement(let isPlaying): return isPlaying
        default: return false
        }
    }

    var isStale: Bool {
        if case .item(_, _, true) = self { return true }
        return false
    }

    /// Play/pause and skip only make sense when we know what's playing.
    var showsControls: Bool {
        switch self {
        case .item(_, _, let isStale): return !isStale
        case .advertisement: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .notConnected: return "Connect Spotify"
        case .waitingForUnlock: return "Unlock to update"
        case .idle: return "Nothing playing"
        case .item(let item, _, _): return item.title
        case .advertisement: return "Advertisement"
        case .problem: return "Can't reach Spotify"
        }
    }

    var subtitle: String {
        switch self {
        case .notConnected: return "Open Spindle to sign in"
        case .item(let item, _, _): return item.subtitle
        case .problem(let message): return message
        default: return ""
        }
    }
}

struct SpindleEntry: TimelineEntry {
    let date: Date
    let display: WidgetDisplay
    let label: CGImage?
    let fetchedAt: Date?
    let lowPower: Bool
}

struct SpindleProvider: TimelineProvider {
    /// Label art is decoded at this size (≈ the largest label × 3 px/pt, StandBy included).
    private let labelPixels = 360

    func placeholder(in context: Context) -> SpindleEntry {
        SpindleEntry(date: Date(), display: .idle, label: nil, fetchedAt: nil, lowPower: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpindleEntry) -> Void) {
        // Widget gallery preview: last known state, cached art only, no network.
        Task {
            let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            guard let snapshot = SharedStore.loadSnapshot(),
                  let first = TimelinePlanner.plan(snapshot, now: Date(), lowPower: lowPower).entries.first
            else {
                completion(placeholder(in: context))
                return
            }
            let images = await ArtworkCache.images(for: first.item.map { [$0] } ?? [], maxPixelSize: labelPixels, download: false)
            completion(SpindleEntry(date: Date(), display: WidgetDisplay(first),
                                    label: first.item.flatMap { ArtworkCache.remoteURL(for: $0) }.flatMap { images[$0] },
                                    fetchedAt: snapshot.fetchedAt, lowPower: lowPower))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpindleEntry>) -> Void) {
        SharedStore.recordHeartbeat(family: String(describing: context.family))
        Task {
            let now = Date()
            let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

            let snapshot: PlaybackSnapshot
            do {
                snapshot = try await Self.loadSnapshot()
            } catch {
                let (display, reload) = Self.failureDisplay(error, now: now)
                let entry = SpindleEntry(date: now, display: display, label: nil, fetchedAt: nil, lowPower: lowPower)
                completion(Timeline(entries: [entry], policy: reload))
                return
            }

            let plan = TimelinePlanner.plan(snapshot, now: now, lowPower: lowPower)
            // Covers for every planned track, downloaded in one burst now so later
            // entries render without network access.
            let images = await ArtworkCache.images(for: plan.entries.compactMap(\.item), maxPixelSize: labelPixels)
            let entries = plan.entries.map { planned in
                SpindleEntry(date: planned.date,
                             display: WidgetDisplay(planned),
                             label: planned.item.flatMap { ArtworkCache.remoteURL(for: $0) }.flatMap { images[$0] },
                             fetchedAt: snapshot.fetchedAt,
                             lowPower: lowPower)
            }
            completion(Timeline(entries: entries, policy: .after(plan.reloadAt)))
        }
    }

    /// Reuse a fetch under a minute old (by the app or another widget); else one burst to Spotify.
    private static func loadSnapshot() async throws -> PlaybackSnapshot {
        if let cached = SharedStore.loadSnapshot(), cached.isFresh(now: Date()) { return cached }
        return try await SpotifyService.fetchPlayback()
    }

    private static func failureDisplay(_ error: Error, now: Date) -> (WidgetDisplay, TimelineReloadPolicy) {
        let generic: (WidgetDisplay, TimelineReloadPolicy) =
            (.problem("Open Spindle for details"), .after(now.addingTimeInterval(30 * 60)))
        guard let failure = error as? SpotifyService.Failure else { return generic }

        switch failure {
        case .notSignedIn, .api(.invalidGrant):
            return (.notConnected, .never)   // the app reloads the widget after sign-in
        case .waitingForUnlock:
            return (.waitingForUnlock, .after(now.addingTimeInterval(15 * 60)))
        case .network:
            return (.problem("Offline"), .after(now.addingTimeInterval(30 * 60)))
        case .api(.forbidden):
            return (.problem("Access refused — open Spindle"), .after(now.addingTimeInterval(60 * 60)))
        case .api(.rateLimited(let retryAfter, let quotaExceeded)):
            let wait: TimeInterval = quotaExceeded ? 24 * 3600 : max(retryAfter ?? 0, 30 * 60)
            return (.problem("Spotify asked to wait"), .after(now.addingTimeInterval(wait)))
        default:
            return generic
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

/// A record that turns at 16⅔ RPM (3.6 s per turn) while `spinning`, under a static sheen.
/// The angle comes from the clock, so it doesn't jump when the track or timeline changes.
struct RecordView: View {
    let label: CGImage?
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
            VinylDisc(label: label).clockHandRotationEffect(period: .custom(3.6))
        } else {
            VinylDisc(label: label)
        }
    }
}

struct SpindleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let entry: SpindleEntry

    /// Spin only while playing on fresh data, and never in Low Power Mode, Always-On,
    /// or with Reduce Motion (where the effect would tick or distract).
    private var spinning: Bool {
        entry.display.isPlaying && !entry.display.isStale && !entry.lowPower && !reduceMotion && !isLuminanceReduced
    }

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
                RecordView(label: entry.label, spinning: spinning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.display.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if !entry.display.subtitle.isEmpty {
                        Text(entry.display.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    HStack(alignment: .center, spacing: 10) {
                        if entry.display.showsControls {
                            playPauseButton
                            skipButton
                        }
                        Spacer(minLength: 0)
                        statusLine
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            RecordView(label: entry.label, spinning: spinning)
                .overlay(alignment: .bottomTrailing) {
                    if entry.display.showsControls {
                        playPauseButton.offset(x: 6, y: 6)
                    }
                }
        }
    }

    private var playPauseButton: some View {
        Button(intent: TogglePlaybackIntent(isPlaying: entry.display.isPlaying)) {
            controlIcon(entry.display.isPlaying ? "pause.fill" : "play.fill")
        }
        .buttonStyle(.plain)
    }

    private var skipButton: some View {
        Button(intent: SkipTrackIntent()) {
            controlIcon("forward.fill")
        }
        .buttonStyle(.plain)
    }

    private func controlIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color(white: 0.2).opacity(0.85)))
    }

    @ViewBuilder
    private var statusLine: some View {
        Group {
            if AppGroup.id == nil {
                Text("No shared folder")
            } else if entry.display.isStale, let fetchedAt = entry.fetchedAt {
                Text("Last seen \(fetchedAt, style: .time)")
            } else if case .item(_, false, _) = entry.display {
                Text("Paused")
            } else if entry.lowPower && entry.display.isPlaying {
                Text("Low Power")
            } else {
                EmptyView()
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.white.opacity(0.5))
        .lineLimit(1)
    }
}
