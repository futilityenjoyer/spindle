import AppIntents
import WidgetKit
import SwiftUI
import ClockHandKit
import Core

// The Spindle widgets (Clean glass design, design/directions.html).
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

    /// The faint line above the title.
    var eyebrow: String {
        switch self {
        case .item(_, let isPlaying, _): return isPlaying ? "Now Playing" : "Paused"
        case .advertisement: return "Now Playing"
        case .idle: return "Spotify"
        case .notConnected, .waitingForUnlock, .problem: return "Spindle"
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

/// "Spindle": small + medium with playback controls, on silver.
struct SpinTestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpinTest", provider: SpindleProvider()) { (entry: SpindleEntry) in
            SpindleWidgetView(entry: entry, style: .controls)
        }
        .configurationDisplayName("Spindle")
        .description("A spinning record with playback controls.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()   // each layout applies the design's own margins
    }
}

/// "Spindle Minimal": medium, no playback buttons, on a colour from the album art.
struct SpindleMinimalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpindleMinimal", provider: SpindleProvider()) { (entry: SpindleEntry) in
            SpindleWidgetView(entry: entry, style: .minimal)
        }
        .configurationDisplayName("Spindle Minimal")
        .description("A spinning record in your album's colours.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
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

enum SpindleStyle {
    case controls
    case minimal
}

struct SpindleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let entry: SpindleEntry
    let style: SpindleStyle

    /// Spin only while playing on fresh data, and never in Low Power Mode, Always-On,
    /// or with Reduce Motion.
    private var spinning: Bool {
        entry.display.isPlaying && !entry.display.isStale && !entry.lowPower && !reduceMotion && !isLuminanceReduced
    }

    /// The tonearm rests on the record while playing; it lifts when paused or stale.
    private var armDown: Bool {
        entry.display.isPlaying && !entry.display.isStale
    }

    private var base: CleanBase {
        style == .minimal ? CleanBase.tinted(entry.palette.tone) : CleanBase.silver
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                CleanBackground(art: entry.art, base: base, isSmall: family == .systemSmall)
            }
    }

    @ViewBuilder
    private var content: some View {
        if family == .systemSmall {
            SmallLayout(entry: entry, spinning: spinning, armDown: armDown)
        } else if style == .minimal {
            MinimalMediumLayout(entry: entry, spinning: spinning, armDown: armDown)
        } else {
            ControlsMediumLayout(entry: entry, spinning: spinning, armDown: armDown)
        }
    }
}

// MARK: - Small (silver, play/pause in the corner)

struct SmallLayout: View {
    let entry: SpindleEntry
    let spinning: Bool
    let armDown: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TurntableView(art: entry.art, armDown: armDown, onLightBase: true,
                          layout: .small, rotation: SpinEffect(spinning: spinning))
                .opacity(entry.display.isDimmed ? 0.38 : 1)
            if entry.display.showsControls {
                PlainControl(symbol: entry.display.isPlaying ? "pause.fill" : "play.fill",
                             intent: TogglePlaybackIntent(isPlaying: entry.display.isPlaying),
                             ink: CleanInk.onSilver)
                    .padding(4)
            }
        }
    }
}

// MARK: - Medium with controls (silver)

struct ControlsMediumLayout: View {
    let entry: SpindleEntry
    let spinning: Bool
    let armDown: Bool
    private var ink: CleanInk { CleanInk.onSilver }

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let width: CGFloat = geo.size.width
            let height: CGFloat = geo.size.height
            let box: CGFloat = height * 0.962
            ZStack(alignment: .topLeading) {
                TurntableView(art: entry.art, armDown: armDown, onLightBase: true,
                              layout: .medium, rotation: SpinEffect(spinning: spinning))
                    .frame(width: box, height: box)
                    .opacity(entry.display.isDimmed ? 0.38 : 1)
                    .position(x: width - 2 - box / 2, y: height / 2)
                textColumn
                    .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 0))
                    .frame(width: width - box - 4, height: height, alignment: .topLeading)
            }
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            EyebrowText(entry: entry)
                .font(.system(size: 13))
                .foregroundStyle(ink.secondary)
                .opacity(0.72)
                .padding(.bottom, 3)
            Text(entry.display.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(ink.primary)
                .lineLimit(2)
            if !entry.display.subtitle.isEmpty {
                Text(entry.display.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if entry.display.showsControls {
                HStack(spacing: 10) {
                    PlainControl(symbol: "backward.end.fill", intent: PreviousTrackIntent(), ink: ink)
                    PlainControl(symbol: entry.display.isPlaying ? "pause.fill" : "play.fill",
                                 intent: TogglePlaybackIntent(isPlaying: entry.display.isPlaying), ink: ink)
                    PlainControl(symbol: "forward.end.fill", intent: SkipTrackIntent(), ink: ink)
                }
                .padding(.leading, -8)
            }
        }
    }
}

// MARK: - Medium minimal (album colour, no playback buttons)

struct MinimalMediumLayout: View {
    let entry: SpindleEntry
    let spinning: Bool
    let armDown: Bool
    private var ink: CleanInk { CleanInk.onTint }

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let width: CGFloat = geo.size.width
            let height: CGFloat = geo.size.height
            let box: CGFloat = height * 0.962
            ZStack(alignment: .topLeading) {
                TurntableView(art: entry.art, armDown: armDown, onLightBase: false,
                              layout: .medium, rotation: SpinEffect(spinning: spinning))
                    .frame(width: box, height: box)
                    .opacity(entry.display.isDimmed ? 0.38 : 1)
                    .position(x: width - 2 - box / 2, y: height / 2)
                textColumn
                    .padding(EdgeInsets(top: 20, leading: 21, bottom: 20, trailing: 0))
                    .frame(width: width - box - 4, height: height, alignment: .topLeading)
                refreshButton
                    .position(x: width - 8 - 11, y: height - 8 - 11)
            }
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            EyebrowText(entry: entry)
                .font(.system(size: 12.5))
                .foregroundStyle(ink.secondary)
            Spacer(minLength: 4)
            if !entry.display.subtitle.isEmpty {
                Text(entry.display.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ink.secondary)
                    .lineLimit(1)
            }
            Text(entry.display.title)
                .font(.system(size: 16.5, weight: .medium))
                .foregroundStyle(ink.primary)
                .lineLimit(2)
                .padding(.top, 1)
        }
    }

    /// Small, faint: re-checks Spotify now (the tap reloads the widget without using its daily budget).
    private var refreshButton: some View {
        Button(intent: RefreshWidgetIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ink.primary.opacity(0.55))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared pieces

/// "Now Playing", "Paused", or "Last seen 4:32" when the data is stale.
struct EyebrowText: View {
    let entry: SpindleEntry

    var body: some View {
        if entry.display.isStale, let fetchedAt = entry.fetchedAt {
            Text("Last seen \(fetchedAt, style: .time)")
        } else {
            Text(entry.display.eyebrow)
        }
    }
}

/// A plain glyph button (no circle behind it).
struct PlainControl<Intent: AppIntent>: View {
    let symbol: String
    let intent: Intent
    let ink: CleanInk

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ink.primary)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }
}
