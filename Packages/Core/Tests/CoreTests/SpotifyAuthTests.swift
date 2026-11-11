import Foundation
import XCTest
@testable import Core
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SpotifyAuthTests: XCTestCase {
    // MARK: PKCE

    func testVerifierUsesUnreservedCharactersAndClampsLength() {
        let verifier = PKCE.makeVerifier(length: 64)
        XCTAssertEqual(verifier.count, 64)
        XCTAssertTrue(verifier.allSatisfy { PKCE.alphabet.contains($0) })
        XCTAssertEqual(PKCE.makeVerifier(length: 10).count, 43)
        XCTAssertEqual(PKCE.makeVerifier(length: 500).count, 128)
    }

    func testBase64URLHasNoPaddingOrUnsafeCharacters() {
        // Bytes chosen to produce "+", "/" and "=" in standard base64.
        let data = Data([0xFB, 0xFF, 0xBF, 0xFE])
        XCTAssertEqual(data.base64EncodedString(), "+/+//g==")
        XCTAssertEqual(PKCE.base64URL(data), "-_-__g")
    }

    func testChallengeHashesTheVerifierBytes() {
        var hashed: Data?
        let challenge = PKCE.challenge(for: "abc") { input in
            hashed = input
            return Data([0xFB, 0xFF])
        }
        XCTAssertEqual(hashed, Data("abc".utf8))
        XCTAssertEqual(challenge, "-_8")
    }

    // MARK: Requests

    func testAuthorizeURLCarriesPKCEParameters() throws {
        let url = SpotifyAPI.authorizeURL(
            clientID: "cid", redirectURI: "https://example.github.io/spindle/callback/",
            scopes: ["user-read-currently-playing", "user-read-playback-state"],
            state: "st", codeChallenge: "ch")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(url.host, "accounts.spotify.com")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge"), "ch")
        XCTAssertEqual(value("state"), "st")
        XCTAssertEqual(value("redirect_uri"), "https://example.github.io/spindle/callback/")
        XCTAssertEqual(value("scope"), "user-read-currently-playing user-read-playback-state")
        XCTAssertNil(value("client_secret"))
    }

    func testFormEncodingEscapesReservedCharacters() {
        let body = SpotifyAPI.formEncode([("redirect_uri", "https://a.b/c/?x=1&y"), ("code", "A b+")])
        XCTAssertEqual(String(decoding: body, as: UTF8.self),
                       "redirect_uri=https%3A%2F%2Fa.b%2Fc%2F%3Fx%3D1%26y&code=A%20b%2B")
    }

    func testTokenRequestIsFormPost() {
        let request = SpotifyAPI.tokenRequest(fields: SpotifyAPI.refreshFields(refreshToken: "r", clientID: "c"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, SpotifyAPI.tokenEndpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(String(decoding: request.httpBody ?? Data(), as: UTF8.self),
                       "grant_type=refresh_token&refresh_token=r&client_id=c")
    }

    func testPlayerRequestsUseBearerToken() {
        let request = SpotifyAPI.currentlyPlayingRequest(accessToken: "tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.spotify.com/v1/me/player/currently-playing?additional_types=track,episode")
        XCTAssertEqual(SpotifyAPI.queueRequest(accessToken: "tok").url?.absoluteString,
                       "https://api.spotify.com/v1/me/player/queue")
    }

    // MARK: Tokens

    func testRefreshKeepsPreviousRefreshTokenWhenOmitted() throws {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let previous = SpotifyToken(accessToken: "old", refreshToken: "r1", expiresAt: now, scope: "s")
        let response = try JSONDecoder().decode(TokenResponse.self,
            from: Data(#"{"access_token":"new","token_type":"Bearer","expires_in":3600}"#.utf8))
        let token = try XCTUnwrap(response.makeToken(previous: previous, now: now))
        XCTAssertEqual(token.accessToken, "new")
        XCTAssertEqual(token.refreshToken, "r1")
        XCTAssertEqual(token.scope, "s")
        XCTAssertEqual(token.expiresAt, now.addingTimeInterval(3600))
    }

    func testRotatedRefreshTokenIsStored() throws {
        let response = try JSONDecoder().decode(TokenResponse.self,
            from: Data(#"{"access_token":"a","expires_in":3600,"refresh_token":"r2","scope":"x"}"#.utf8))
        XCTAssertEqual(response.makeToken(previous: nil, now: Date())?.refreshToken, "r2")
    }

    func testNoRefreshTokenAtAllIsRejected() throws {
        let response = try JSONDecoder().decode(TokenResponse.self,
            from: Data(#"{"access_token":"a","expires_in":3600}"#.utf8))
        XCTAssertNil(response.makeToken(previous: nil, now: Date()))
    }

    func testNeedsRefreshTwoMinutesEarly() {
        let expiry = Date(timeIntervalSinceReferenceDate: 10_000)
        let token = SpotifyToken(accessToken: "a", refreshToken: "r", expiresAt: expiry, scope: "")
        XCTAssertFalse(token.needsRefresh(now: expiry.addingTimeInterval(-121)))
        XCTAssertTrue(token.needsRefresh(now: expiry.addingTimeInterval(-119)))
    }

    // MARK: Errors

    func testErrorClassification() {
        XCTAssertNil(SpotifyAPIError.from(status: 204, retryAfterHeader: nil, body: Data()))
        XCTAssertEqual(SpotifyAPIError.from(status: 401, retryAfterHeader: nil, body: Data()), .unauthorized)
        XCTAssertEqual(
            SpotifyAPIError.from(status: 400, retryAfterHeader: nil,
                                 body: Data(#"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#.utf8)),
            .invalidGrant)
        XCTAssertEqual(
            SpotifyAPIError.from(status: 403, retryAfterHeader: nil,
                                 body: Data(#"{"error":{"status":403,"message":"User not registered"}}"#.utf8)),
            .forbidden(message: "User not registered"))
        XCTAssertEqual(
            SpotifyAPIError.from(status: 429, retryAfterHeader: "30", body: Data(#"{"reason":"QUOTA_EXCEEDED"}"#.utf8)),
            .rateLimited(retryAfter: 30, quotaExceeded: true))
        XCTAssertEqual(SpotifyAPIError.from(status: 503, retryAfterHeader: nil, body: Data()), .server(status: 503))
    }
}
