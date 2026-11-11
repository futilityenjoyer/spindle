import Foundation
import Core

/// Talks to Spotify for both the app and the widget: token exchange and refresh,
/// and the one-burst player fetch (current track + queue).
enum SpotifyService {
    enum Failure: Error {
        case notSignedIn
        /// Phone restarted and not unlocked yet; try later. Not a sign-out.
        case waitingForUnlock
        case noSharedFolder
        case api(SpotifyAPIError)
        case network(String)
        case badResponse
    }

    // MARK: Sign-in

    /// Exchanges the one-time code from the sign-in page for tokens and stores them.
    static func completeSignIn(code: String, verifier: String) async throws {
        let request = SpotifyAPI.tokenRequest(fields: SpotifyAPI.codeExchangeFields(
            code: code, redirectURI: SpotifyConfig.redirectURI,
            clientID: SpotifyConfig.clientID, verifier: verifier))
        let (data, _) = try await send(request)
        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data),
              let token = response.makeToken(previous: nil, now: Date())
        else { throw Failure.badResponse }
        do { try TokenStore.save(token) } catch { throw Failure.noSharedFolder }
    }

    static func signOut() {
        TokenStore.delete()
        SharedStore.deleteSnapshot()
        ArtworkCache.purge()
    }

    // MARK: Control (widget buttons; Premium only)

    /// Sends play/pause/skip, then discards the cached snapshot so the reload that
    /// follows the button tap fetches the new state instead of reusing the old one.
    static func perform(_ command: SpotifyAPI.PlayerCommand) async throws {
        defer { SharedStore.deleteSnapshot() }
        do {
            _ = try await send(SpotifyAPI.commandRequest(command, accessToken: try await validAccessToken()))
        } catch Failure.api(.unauthorized) {
            _ = try await send(SpotifyAPI.commandRequest(command, accessToken: try await validAccessToken(forceRefresh: true)))
        }
    }

    // MARK: Tokens

    /// A usable access token, refreshing it (once, across app and widget) if needed.
    static func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        let token = try loadToken()
        if !forceRefresh && !token.needsRefresh(now: Date()) { return token.accessToken }
        guard let lockURL = TokenStore.lockURL else { throw Failure.noSharedFolder }

        do {
            return try await CrossProcessLock.withLock(at: lockURL) { () async throws -> String in
                // Re-read inside the lock: the other process may have refreshed while we waited.
                let current = try loadToken()
                let refreshedByOther = current.accessToken != token.accessToken
                if (refreshedByOther || !forceRefresh) && !current.needsRefresh(now: Date()) {
                    return current.accessToken
                }
                let fresh = try await refresh(current)
                do { try TokenStore.save(fresh) } catch { throw Failure.noSharedFolder }
                return fresh.accessToken
            }
        } catch let error as CrossProcessLock.Timeout {
            throw Failure.network("Timed out waiting for another refresh (\(error))")
        }
    }

    private static func loadToken() throws -> SpotifyToken {
        do {
            guard let token = try TokenStore.load() else { throw Failure.notSignedIn }
            return token
        } catch is TokenStore.TemporarilyUnavailable {
            throw Failure.waitingForUnlock
        }
    }

    private static func refresh(_ token: SpotifyToken) async throws -> SpotifyToken {
        let request = SpotifyAPI.tokenRequest(fields: SpotifyAPI.refreshFields(
            refreshToken: token.refreshToken, clientID: SpotifyConfig.clientID))
        do {
            let (data, _) = try await send(request)
            guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data),
                  let fresh = response.makeToken(previous: token, now: Date())
            else { throw Failure.badResponse }
            return fresh
        } catch Failure.api(.invalidGrant) {
            // The refresh token is dead (expired after 6 months, or access removed).
            signOut()
            throw Failure.api(.invalidGrant)
        }
    }

    // MARK: Player

    /// Current track and queue in one radio burst; also saved for the other process.
    /// Retries once with a refreshed token if Spotify says the token is no longer valid.
    static func fetchPlayback() async throws -> PlaybackSnapshot {
        do {
            return try await fetchPlayback(accessToken: try await validAccessToken())
        } catch Failure.api(.unauthorized) {
            return try await fetchPlayback(accessToken: try await validAccessToken(forceRefresh: true))
        }
    }

    private static func fetchPlayback(accessToken: String) async throws -> PlaybackSnapshot {
        async let current = send(SpotifyAPI.currentlyPlayingRequest(accessToken: accessToken))
        async let upcoming = send(SpotifyAPI.queueRequest(accessToken: accessToken))

        let (currentData, currentStatus) = try await current
        let nowPlaying: NowPlaying?
        if currentStatus == 204 || currentData.isEmpty {
            nowPlaying = nil   // nothing playing
        } else {
            do { nowPlaying = try SpotifyParser.nowPlaying(from: currentData) } catch { throw Failure.badResponse }
        }

        // The queue is a nice-to-have: a failure there must not hide the current track.
        let queue: [PlayableItem]
        if let result = try? await upcoming, result.1 == 200 {
            queue = (try? SpotifyParser.queue(from: result.0)) ?? []
        } else {
            queue = []
        }

        let snapshot = PlaybackSnapshot(fetchedAt: Date(), nowPlaying: nowPlaying, queue: queue)
        SharedStore.saveSnapshot(snapshot)
        return snapshot
    }

    // MARK: Transport

    private static func send(_ request: URLRequest) async throws -> (Data, Int) {
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }
        if let error = SpotifyAPIError.from(status: http.statusCode,
                                            retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After"),
                                            body: data) {
            throw Failure.api(error)
        }
        return (data, http.statusCode)
    }
}

extension SpotifyService.Failure {
    /// A short, actionable explanation for the app's Spotify section.
    var explanation: String {
        switch self {
        case .notSignedIn:
            return "Not connected."
        case .waitingForUnlock:
            return "Unlock your iPhone, then try again."
        case .noSharedFolder:
            return "The shared folder is unavailable, so the sign-in can't be saved. Check Diagnostics › App Group."
        case .api(.invalidGrant):
            return "Your Spotify sign-in expired or was removed. Connect again."
        case .api(.forbidden(let message)):
            return "Spotify refused access (403\(message.isEmpty ? "" : ": \(message)")). Check that your account is listed under User Management in the Spotify dashboard and that Premium is active."
        case .api(.rateLimited(_, let quotaExceeded)):
            return quotaExceeded
                ? "Spotify's daily quota for this app is used up. It resets within 24 hours."
                : "Spotify asked us to slow down. Try again in a minute."
        case .api(.unauthorized):
            return "Spotify rejected the sign-in. Connect again."
        case .api(.badRequest(let message)):
            return "Spotify rejected the request: \(message)"
        case .api(.server(let status)), .api(.unexpected(let status)):
            return "Spotify returned an error (\(status)). Try again later."
        case .network(let message):
            return "Network problem: \(message)"
        case .badResponse:
            return "Spotify sent a response Spindle couldn't read."
        }
    }
}
