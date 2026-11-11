import Foundation

/// The Spotify credentials we keep (in a protected file in the App Group).
/// Holds only a scoped token for this app — never a password.
public struct SpotifyToken: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var scope: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, scope: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    /// Refresh a little early so no request goes out with a token about to expire.
    public func needsRefresh(now: Date, leeway: TimeInterval = 120) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}

/// Body of a successful `POST https://accounts.spotify.com/api/token`.
public struct TokenResponse: Decodable, Equatable, Sendable {
    public let accessToken: String
    public let expiresIn: Int
    public let refreshToken: String?
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }

    /// Builds the token to store. On refresh Spotify may omit `refresh_token`,
    /// in which case the previous one stays valid. Returns nil if there is none.
    public func makeToken(previous: SpotifyToken?, now: Date) -> SpotifyToken? {
        guard let refresh = refreshToken ?? previous?.refreshToken else { return nil }
        return SpotifyToken(
            accessToken: accessToken,
            refreshToken: refresh,
            expiresAt: now.addingTimeInterval(TimeInterval(expiresIn)),
            scope: scope ?? previous?.scope ?? ""
        )
    }
}
