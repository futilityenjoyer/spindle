import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI
import Core

/// Spotify sign-in with PKCE, shown in Apple's secure web sign-in sheet.
///
/// Flow: Spotify's page → our GitHub Pages return page (HTTPS, required by Spotify)
/// → `dev.spindlevinyl.auth://callback?code=…&state=…`, which the sheet intercepts.
/// The code is only usable together with the verifier, which never leaves this device.
enum SpotifyLogin {
    enum LoginError: LocalizedError {
        case stateMismatch
        case denied(String)
        case missingCode

        var errorDescription: String? {
            switch self {
            case .stateMismatch: return "The sign-in response didn't match this request. Please try again."
            case .denied(let reason): return reason == "access_denied" ? "Sign-in was cancelled on Spotify's page." : "Spotify sign-in failed: \(reason)"
            case .missingCode: return "Spotify didn't return a sign-in code. Please try again."
            }
        }
    }

    @MainActor
    static func signIn(using session: WebAuthenticationSession) async throws {
        let verifier = PKCE.makeVerifier()
        let challenge = PKCE.challenge(for: verifier) { Data(SHA256.hash(data: $0)) }
        let state = PKCE.makeVerifier(length: 43)   // random value to reject forged responses

        let url = SpotifyAPI.authorizeURL(
            clientID: SpotifyConfig.clientID,
            redirectURI: SpotifyConfig.redirectURI,
            scopes: SpotifyConfig.scopes,
            state: state,
            codeChallenge: challenge)

        let callback = try await session.authenticate(using: url, callbackURLScheme: SpotifyConfig.callbackScheme)

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard value("state") == state else { throw LoginError.stateMismatch }
        if let error = value("error") { throw LoginError.denied(error) }
        guard let code = value("code") else { throw LoginError.missingCode }

        try await SpotifyService.completeSignIn(code: code, verifier: verifier)
    }
}
