import Foundation

/// Values registered in the Spotify developer dashboard. None of these are secret:
/// PKCE sign-in needs no client secret, so this file is safe in a public repo.
enum SpotifyConfig {
    static let clientID = "5ff4147b256b41e1a08c240afbef490d"

    /// Spotify only accepts HTTPS (or loopback) redirect URIs for new apps. This GitHub
    /// Pages page (docs/callback/index.html) forwards the result to `callbackScheme`.
    /// Must match the dashboard entry exactly, including the trailing slash.
    static let redirectURI = "https://futilityenjoyer.github.io/spindle/callback/"

    /// Intercepted by the web authentication session; never registered system-wide.
    static let callbackScheme = "dev.spindlevinyl.auth"

    /// Read playback, plus control for the widget's play/pause/skip buttons (M4) —
    /// requested now so adding the buttons later doesn't force a second sign-in.
    static let scopes = [
        "user-read-currently-playing",
        "user-read-playback-state",
        "user-modify-playback-state",
    ]
}
