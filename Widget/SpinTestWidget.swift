import AppIntents
import WidgetKit
import SwiftUI
import ClockHandKit
import Core

// The Spindle widget (design spec §5, Sleeve medium + Inscribed small).
// The kind stays "SpinTest" (its M0 name) so widgets already on the Home Screen keep working.
// Keep view expressions small and explicitly typed (see the note in VinylRecord.swift).

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

    var isPaused: Bool {
        if case .item(_, false, false) = self { return true }
        return false
    }

    var showsControls: Bool {
        switch self {
        case .item(_, _, let isStale): return !isStale
        case .advertisement: return true
        default: return false
        }
    }

    var isDimmed: Bool {
        if case .notConnected = self { return true }
        return false
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
        case .notConnected: return "Tap to sign in"
        case .idle: return "Play something in Spotify"
        case .item(let item, _, _): return item.subtitle
        case .advertisement: return "Spotify"
        case .problem(let message): return message
        case .waitingForUnlock: return ""
        }
    }
}

struct SpindleEntry: TimelineEntry {
    let date: Date
    let display: WidgetDisplay
    let art: CGImage?
    let palette: ArtPalette
    let fetchedAt: Date?
    let lowPower: Bool
}

struct SpindleProvider: TimelineProvider {
    /// Covers are decoded at this size (≈ largest cover × 3 px/pt, StandBy included).
    private let artPixels = 400

    func placeholder(in context: Context) -> SpindleEntry {
        SpindleEntry(date: Date(), display: .idle, art: nil, palette: .neutral, fetchedAt: nil, lowPower: false)
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
            let covers = await Covers.load(for: [first], pixels: artPixels, download: false)
            completion(Self.entry(for: first, covers: covers, fetchedAt: snapshot.fetchedAt, lowPower: lowPower))
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
                let entry = SpindleEntry(date: now, display: display, art: nil, palette: .neutral,
                                         fetchedAt: nil, lowPower: lowPower)
                completion(Timeline(entries: [entry], policy: reload))
                return
            }

            let plan = TimelinePlanner.plan(snapshot, now: now, lowPower: lowPower,
                                            settings: SharedSettings.plannerSettings)
            // Covers for every planned track, downloaded in one burst now so later
            // entries render without network access.
            let covers = await Covers.load(for: plan.entries, pixels: artPixels, download: true)
            let entries: [SpindleEntry] = plan.entries.map { (planned: PlannedEntry) -> SpindleEntry in
                Self.entry(for: planned, covers: covers, fetchedAt: snapshot.fetchedAt, lowPower: lowPower)
            }
            completion(Timeline(entries: entries, policy: .after(plan.reloadAt)))
        }
    }

    private static func entry(for planned: PlannedEntry, covers: Covers, fetchedAt: Date, lowPower: Bool) -> SpindleEntry {
        let remote: URL? = planned.item.flatMap { ArtworkCache.remoteURL(for: $0) }
        let art: CGImage? = remote.flatMap { covers.images[$0] }
        let palette: ArtPalette = remote.flatMap { covers.palettes[$0] } ?? .neutral
        return SpindleEntry(date: planned.date, display: WidgetDisplay(planned), art: art,
                            palette: palette, fetchedAt: fetchedAt, lowPower: lowPower)
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

/// Decoded covers and their palettes, keyed by Spotify image URL.
struct Covers {
    var images: [URL: CGImage] = [:]
    var palettes: [URL: ArtPalette] = [:]

    static func load(for entries: [PlannedEntry], pixels: Int, download: Bool) async -> Covers {
        let items: [PlayableItem] = entries.compactMap { $0.item }
        var covers = Covers()
        covers.images = await ArtworkCache.images(for: items, maxPixelSize: pixels, download: download)
        for (url, image) in covers.images {
            covers.palettes[url] = ArtPaletteExtractor.palette(from: image)
        }
        return covers
    }
}

struct SpinTestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpinTest", provider: SpindleProvider()) { (entry: SpindleEntry) in
            SpindleWidgetView(entry: entry)
        }
        .configurationDisplayName("Spindle")
        .description("A spinning record for what's playing on Spotify.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()   // each layout applies the spec's own margins
    }
}

/// Turns at 16⅔ RPM (3.6 s per turn) while `spinning`. The angle comes from the clock,
/// so it doesn't jump when the track or the timeline changes.
struct SpinEffect: ViewModifier {
    let spinning: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if spinning {
            content.clockHandRotationEffect(period: .custom(3.6))
        } else {
            content
        }
    }
}

struct SpindleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let entry: SpindleEntry

    /// Spin only while playing on fresh data, and never in Low Power Mode, Always-On,
    /// or with Reduce Motion.
    private var spinning: Bool {
        entry.display.isPlaying && !entry.display.isStale && !entry.lowPower && !reduceMotion && !isLuminanceReduced
    }

    var body: some View {
        let ink = WidgetInk(palette: entry.palette, scheme: colorScheme)
        Group {
            if family == .systemMedium {
                MediumSleeveLayout(entry: entry, ink: ink, spinning: spinning)
            } else {
                SmallRecordLayout(entry: entry, ink: ink, spinning: spinning)
            }
        }
        .containerBackground(for: .widget) {
            ink.surface
        }
    }
}

// MARK: - Small: Inscribed record (spec §5.2)

struct SmallRecordLayout: View {
    let entry: SpindleEntry
    let ink: WidgetInk
    let spinning: Bool

    var body: some View {
        ZStack {
            VinylRecord(style: .inscribed, art: entry.art, palette: entry.palette,
                        labelFraction: 0.6, rotation: SpinEffect(spinning: spinning))
                .padding(19)   // disc ≈ 76% of the widget
                .opacity(entry.display.isDimmed ? 0.38 : 1)

            VStack {
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    if !entry.display.isPlaying || entry.display.isStale {
                        StatusLabel(entry: entry, ink: ink)
                    }
                    Spacer(minLength: 0)
                    if entry.display.showsControls {
                        PlayPauseButton(isPlaying: entry.display.isPlaying, ink: ink)
                    }
                }
            }
            .padding(11)
        }
    }
}

// MARK: - Medium: Sleeve (spec §5.4)

struct MediumSleeveLayout: View {
    let entry: SpindleEntry
    let ink: WidgetInk
    let spinning: Bool

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let side: CGFloat = geo.size.height
            let peek: CGFloat = side * 0.38
            HStack(alignment: .center, spacing: 14) {
                ZStack(alignment: .leading) {
                    VinylRecord(style: .plain, art: nil, palette: entry.palette,
                                labelFraction: 0.5, rotation: SpinEffect(spinning: spinning))
                        .frame(width: side, height: side)
                        .offset(x: peek)
                        .opacity(entry.display.isDimmed ? 0.38 : 1)
                    CoverArt(art: entry.art, cornerRadius: 4)
                        .frame(width: side, height: side)
                        .shadow(color: Color.black.opacity(0.35), radius: 3.5, x: 2, y: 1)
                }
                .frame(width: side + peek, height: side, alignment: .leading)

                TextColumn(entry: entry, ink: ink)
            }
        }
        .padding(16)
    }
}

struct TextColumn: View {
    let entry: SpindleEntry
    let ink: WidgetInk

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.display.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink.primary)
                .lineLimit(2)
            if !entry.display.subtitle.isEmpty {
                Text(entry.display.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            StatusLabel(entry: entry, ink: ink)
            if entry.display.showsControls {
                HStack(spacing: 8) {
                    ControlButton(symbol: "backward.fill", intent: PreviousTrackIntent(), ink: ink)
                    PlayPauseButton(isPlaying: entry.display.isPlaying, ink: ink)
                    ControlButton(symbol: "forward.fill", intent: SkipTrackIntent(), ink: ink)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Shared pieces

struct StatusLabel: View {
    let entry: SpindleEntry
    let ink: WidgetInk

    var body: some View {
        HStack(spacing: 4) {
            icon
            text
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(ink.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var icon: some View {
        if AppGroup.id == nil || entry.display.isStale {
            Circle().fill(Color.orange).frame(width: 6, height: 6)
        } else if entry.display.isPlaying {
            Image(systemName: "waveform").font(.system(size: 9, weight: .bold))
        } else if entry.display.isPaused {
            Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold))
        } else {
            Circle().fill(ink.secondary).frame(width: 5, height: 5)
        }
    }

    @ViewBuilder
    private var text: some View {
        if AppGroup.id == nil {
            Text("No shared folder")
        } else if entry.display.isStale, let fetchedAt = entry.fetchedAt {
            Text("Last seen \(fetchedAt, style: .time)")
        } else if entry.display.isPlaying {
            Text(entry.lowPower ? "Playing · Low Power" : "Playing")
        } else if entry.display.isPaused {
            Text("Paused")
        } else if entry.display.isDimmed {
            Text("Signed out")
        } else {
            Text("Idle")
        }
    }
}

struct PlayPauseButton: View {
    let isPlaying: Bool
    let ink: WidgetInk

    var body: some View {
        ControlButton(symbol: isPlaying ? "pause.fill" : "play.fill",
                      intent: TogglePlaybackIntent(isPlaying: isPlaying), ink: ink)
    }
}

struct ControlButton<Intent: AppIntent>: View {
    let symbol: String
    let intent: Intent
    let ink: WidgetInk

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink.primary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(ink.control))
        }
        .buttonStyle(.plain)
    }
}
