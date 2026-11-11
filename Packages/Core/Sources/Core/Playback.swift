import Foundation

public struct ArtworkImage: Codable, Equatable, Sendable {
    public var url: String
    public var width: Int?
    public var height: Int?

    public init(url: String, width: Int?, height: Int?) {
        self.url = url
        self.width = width
        self.height = height
    }
}

/// A track or podcast episode, reduced to what the widget shows.
public struct PlayableItem: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case track, episode, unknown }

    public var kind: Kind
    public var id: String?
    public var uri: String?
    public var title: String
    /// Artists for a track, show name for an episode.
    public var subtitle: String
    public var albumName: String?
    public var durationMs: Int
    public var isLocal: Bool
    public var images: [ArtworkImage]

    public init(kind: Kind, id: String?, uri: String?, title: String, subtitle: String,
                albumName: String?, durationMs: Int, isLocal: Bool, images: [ArtworkImage]) {
        self.kind = kind
        self.id = id
        self.uri = uri
        self.title = title
        self.subtitle = subtitle
        self.albumName = albumName
        self.durationMs = durationMs
        self.isLocal = isLocal
        self.images = images
    }

    /// The smallest image at least `minWidth` pixels wide, else the largest available.
    public func image(minWidth: Int) -> ArtworkImage? {
        let sorted = images.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        return sorted.first { ($0.width ?? 0) >= minWidth } ?? sorted.last
    }
}

/// What Spotify says is playing right now.
public struct NowPlaying: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case track, episode, ad, unknown }

    public var kind: Kind
    public var isPlaying: Bool
    public var progressMs: Int?
    /// nil for ads and when Spotify withholds the item (e.g. private session).
    public var item: PlayableItem?

    public init(kind: Kind, isPlaying: Bool, progressMs: Int?, item: PlayableItem?) {
        self.kind = kind
        self.isPlaying = isPlaying
        self.progressMs = progressMs
        self.item = item
    }
}

/// One fetch of player state, shared by the app and the widget through the App Group.
public struct PlaybackSnapshot: Codable, Equatable, Sendable {
    public var fetchedAt: Date
    /// nil when Spotify reports nothing playing (HTTP 204).
    public var nowPlaying: NowPlaying?
    public var queue: [PlayableItem]

    public init(fetchedAt: Date, nowPlaying: NowPlaying?, queue: [PlayableItem]) {
        self.fetchedAt = fetchedAt
        self.nowPlaying = nowPlaying
        self.queue = queue
    }

    /// Young enough to reuse instead of calling Spotify again (saves radio wake-ups).
    public func isFresh(now: Date, maxAge: TimeInterval = 60) -> Bool {
        abs(now.timeIntervalSince(fetchedAt)) < maxAge
    }

    public static func encode(_ snapshot: PlaybackSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }

    public static func decode(_ data: Data) -> PlaybackSnapshot? {
        try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }
}

/// Parses Spotify Web API player responses.
public enum SpotifyParser {
    public struct InvalidResponse: Error {}

    /// `GET /v1/me/player/currently-playing` with a 200 body.
    public static func nowPlaying(from data: Data) throws -> NowPlaying {
        guard let raw = try? JSONDecoder().decode(RawCurrentlyPlaying.self, from: data) else {
            throw InvalidResponse()
        }
        let kind = NowPlaying.Kind(rawValue: raw.currently_playing_type ?? "") ?? .unknown
        return NowPlaying(
            kind: kind,
            isPlaying: raw.is_playing ?? false,
            progressMs: raw.progress_ms,
            item: kind == .ad ? nil : raw.item.map(playable)
        )
    }

    /// `GET /v1/me/player/queue`: the upcoming items, in order.
    public static func queue(from data: Data) throws -> [PlayableItem] {
        guard let raw = try? JSONDecoder().decode(RawQueue.self, from: data) else {
            throw InvalidResponse()
        }
        return (raw.queue ?? []).map(playable)
    }

    private static func playable(_ raw: RawItem) -> PlayableItem {
        let artists = (raw.artists ?? []).compactMap(\.name).joined(separator: ", ")
        let images = raw.album?.images ?? raw.images ?? raw.show?.images ?? []
        return PlayableItem(
            kind: PlayableItem.Kind(rawValue: raw.type ?? "") ?? .unknown,
            id: raw.id,
            uri: raw.uri,
            title: raw.name ?? "Unknown",
            subtitle: artists.isEmpty ? (raw.show?.name ?? "") : artists,
            albumName: raw.album?.name,
            durationMs: raw.duration_ms ?? 0,
            isLocal: raw.is_local ?? false,
            images: images.map { ArtworkImage(url: $0.url, width: $0.width, height: $0.height) }
        )
    }

    // Raw shapes mirror Spotify's JSON field names exactly; everything is optional
    // because podcasts, ads and local files omit different fields.
    private struct RawCurrentlyPlaying: Decodable {
        let is_playing: Bool?
        let progress_ms: Int?
        let currently_playing_type: String?
        let item: RawItem?
    }

    private struct RawQueue: Decodable {
        let queue: [RawItem]?
    }

    private struct RawItem: Decodable {
        let id: String?
        let uri: String?
        let name: String?
        let type: String?
        let duration_ms: Int?
        let is_local: Bool?
        let artists: [RawNamed]?
        let album: RawAlbum?
        let show: RawShow?
        let images: [RawImage]?
    }

    private struct RawNamed: Decodable { let name: String? }
    private struct RawAlbum: Decodable { let name: String?; let images: [RawImage]? }
    private struct RawShow: Decodable { let name: String?; let images: [RawImage]? }
    private struct RawImage: Decodable { let url: String; let width: Int?; let height: Int? }
}
