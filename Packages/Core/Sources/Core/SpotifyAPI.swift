import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLRequest lives here on Windows and Linux
#endif

/// Builds Spotify requests and classifies responses. No networking happens here,
/// so all of it is unit-testable on Windows.
public enum SpotifyAPI {
    public static let authorizeEndpoint = URL(string: "https://accounts.spotify.com/authorize")!
    public static let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!
    public static let apiBase = URL(string: "https://api.spotify.com/v1")!

    /// Requests on the critical path give up quickly; the widget has little time.
    public static let timeout: TimeInterval = 8

    // MARK: Sign-in (PKCE)

    public static func authorizeURL(clientID: String, redirectURI: String, scopes: [String],
                                    state: String, codeChallenge: String) -> URL {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
        ]
        return components.url!
    }

    public static func codeExchangeFields(code: String, redirectURI: String, clientID: String,
                                          verifier: String) -> [(String, String)] {
        [("grant_type", "authorization_code"), ("code", code), ("redirect_uri", redirectURI),
         ("client_id", clientID), ("code_verifier", verifier)]
    }

    public static func refreshFields(refreshToken: String, clientID: String) -> [(String, String)] {
        [("grant_type", "refresh_token"), ("refresh_token", refreshToken), ("client_id", clientID)]
    }

    public static func tokenRequest(fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: tokenEndpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(fields)
        return request
    }

    /// `application/x-www-form-urlencoded`, escaping everything but RFC 3986 unreserved characters.
    public static func formEncode(_ fields: [(String, String)]) -> Data {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func escape(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
        }
        return Data(fields.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&").utf8)
    }

    // MARK: Player (read-only)

    public static func currentlyPlayingRequest(accessToken: String) -> URLRequest {
        playerRequest(path: "me/player/currently-playing", accessToken: accessToken,
                      query: [URLQueryItem(name: "additional_types", value: "track,episode")])
    }

    public static func queueRequest(accessToken: String) -> URLRequest {
        playerRequest(path: "me/player/queue", accessToken: accessToken, query: [])
    }

    static func playerRequest(path: String, accessToken: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}

/// Why a Spotify call failed, in terms the app and widget can act on.
public enum SpotifyAPIError: Error, Equatable, Sendable {
    /// 401 — the access token is expired or invalid; refresh once and retry.
    case unauthorized
    /// 403 — e.g. account not added under User Management, or the owner's Premium lapsed.
    case forbidden(message: String)
    /// 429 — slow down. `quotaExceeded` marks Spotify's daily Development Mode quota.
    case rateLimited(retryAfter: TimeInterval?, quotaExceeded: Bool)
    /// 400 invalid_grant from the token endpoint — the refresh token is dead (e.g. after
    /// 6 months, or access was removed). The user must connect again.
    case invalidGrant
    case badRequest(message: String)
    case server(status: Int)
    case unexpected(status: Int)

    /// Classifies a response; nil for 2xx.
    public static func from(status: Int, retryAfterHeader: String?, body: Data) -> SpotifyAPIError? {
        switch status {
        case 200...299:
            return nil
        case 400:
            let info = errorInfo(body)
            return info.code == "invalid_grant" ? .invalidGrant : .badRequest(message: info.message)
        case 401:
            return .unauthorized
        case 403:
            return .forbidden(message: errorInfo(body).message)
        case 429:
            let text = String(decoding: body, as: UTF8.self)
            return .rateLimited(retryAfter: retryAfterHeader.flatMap { TimeInterval($0) },
                                quotaExceeded: text.contains("QUOTA_EXCEEDED"))
        case 500...599:
            return .server(status: status)
        default:
            return .unexpected(status: status)
        }
    }

    /// Spotify uses two error shapes: OAuth (`{"error":"invalid_grant","error_description":…}`)
    /// on the accounts service, and `{"error":{"status":…,"message":…}}` on the Web API.
    static func errorInfo(_ body: Data) -> (code: String?, message: String) {
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return (nil, String(decoding: body.prefix(200), as: UTF8.self))
        }
        if let code = object["error"] as? String {
            return (code, object["error_description"] as? String ?? code)
        }
        if let nested = object["error"] as? [String: Any] {
            return (nil, nested["message"] as? String ?? "")
        }
        return (nil, "")
    }
}
