import Foundation

/// One moment in the widget's timeline.
public struct PlannedEntry: Equatable, Sendable {
    public var date: Date
    /// The track or episode to show; nil when idle or during an ad.
    public var item: PlayableItem?
    /// Whether the record should spin (the view may still hold it still, e.g. Reduce Motion).
    public var isPlaying: Bool
    public var isAdvertisement: Bool
    /// "Last seen": we planned this far without fresh data, so stop spinning rather than
    /// keep spinning on stale information.
    public var isStale: Bool

    public init(date: Date, item: PlayableItem?, isPlaying: Bool, isAdvertisement: Bool = false, isStale: Bool = false) {
        self.date = date
        self.item = item
        self.isPlaying = isPlaying
        self.isAdvertisement = isAdvertisement
        self.isStale = isStale
    }
}

public struct TimelinePlan: Equatable, Sendable {
    public var entries: [PlannedEntry]
    /// When iOS should ask for a new timeline (each request uses daily reload budget).
    public var reloadAt: Date

    public init(entries: [PlannedEntry], reloadAt: Date) {
        self.entries = entries
        self.reloadAt = reloadAt
    }
}

/// Turns one Spotify snapshot into a widget timeline (FEASIBILITY.md §4.7).
///
/// iOS doesn't tell widgets when Spotify changes track or pauses, and reloads are
/// budgeted (~40–70/day). So we *predict*: Spotify's queue tells us what plays next
/// and when the current track ends, and timeline entries — which cost no budget —
/// switch the label at each predicted boundary. A final "last seen" entry stops the
/// record if no fresh data arrives, so it never spins on indefinitely after a pause.
public enum TimelinePlanner {
    public struct Settings: Sendable {
        public var playingReload: TimeInterval = 10 * 60
        public var lowPowerPlayingReload: TimeInterval = 15 * 60
        public var pausedReload: TimeInterval = 30 * 60
        public var idleReload: TimeInterval = 60 * 60
        /// Extra time after the planned reload before we admit the data is stale.
        public var grace: TimeInterval = 2 * 60
        /// Upper bound on predicted tracks per timeline.
        public var maxPredicted = 8

        public init() {}
    }

    public static func plan(_ snapshot: PlaybackSnapshot, now: Date, lowPower: Bool,
                            settings: Settings = Settings()) -> TimelinePlan {
        guard let playing = snapshot.nowPlaying else {
            return TimelinePlan(entries: [PlannedEntry(date: now, item: nil, isPlaying: false)],
                                reloadAt: now.addingTimeInterval(settings.idleReload))
        }

        let isAd = playing.kind == .ad
        guard playing.isPlaying else {
            return TimelinePlan(
                entries: [PlannedEntry(date: now, item: playing.item, isPlaying: false, isAdvertisement: isAd)],
                reloadAt: now.addingTimeInterval(settings.pausedReload))
        }

        let reloadAt = now.addingTimeInterval(lowPower ? settings.lowPowerPlayingReload : settings.playingReload)
        let lastSeenAt = reloadAt.addingTimeInterval(settings.grace)
        var entries = [PlannedEntry(date: now, item: playing.item, isPlaying: true, isAdvertisement: isAd)]

        if let item = playing.item, item.durationMs > 0, let progress = playing.progressMs {
            let remaining = TimeInterval(max(item.durationMs - progress, 0)) / 1000
            var boundary = snapshot.fetchedAt.addingTimeInterval(remaining)

            for next in snapshot.queue.prefix(settings.maxPredicted) {
                guard boundary < lastSeenAt else { break }
                if boundary <= now {
                    // The snapshot is a little old and that track already ended: show the next one now.
                    entries[entries.count - 1].item = next
                    entries[entries.count - 1].isAdvertisement = false
                } else {
                    entries.append(PlannedEntry(date: boundary, item: next, isPlaying: true))
                }
                guard next.durationMs > 0 else { break }   // unknown length: can't predict further
                boundary = boundary.addingTimeInterval(TimeInterval(next.durationMs) / 1000)
            }
        }

        entries.append(PlannedEntry(date: lastSeenAt, item: entries.last?.item, isPlaying: false, isStale: true))
        return TimelinePlan(entries: entries, reloadAt: reloadAt)
    }
}
