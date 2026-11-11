import Foundation

/// Proof Key for Code Exchange (RFC 7636): lets the app sign in to Spotify without
/// a client secret. The verifier never leaves the device; only its SHA-256 hash
/// (the challenge) is sent with the sign-in request.
public enum PKCE {
    /// RFC 7636 "unreserved" characters.
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// A random verifier (43–128 characters per RFC 7636).
    public static func makeVerifier<G: RandomNumberGenerator>(length: Int = 64, using rng: inout G) -> String {
        let count = min(max(length, 43), 128)
        return String((0..<count).map { _ in alphabet.randomElement(using: &rng)! })
    }

    /// Uses the system's cryptographically secure generator.
    public static func makeVerifier(length: Int = 64) -> String {
        var rng = SystemRandomNumberGenerator()
        return makeVerifier(length: length, using: &rng)
    }

    /// `BASE64URL(SHA256(verifier))`. The hash function is injected so this package
    /// stays Foundation-only (CryptoKit is Apple-only); the app passes CryptoKit's SHA256.
    public static func challenge(for verifier: String, sha256: (Data) -> Data) -> String {
        base64URL(sha256(Data(verifier.utf8)))
    }

    /// Base64url without padding (RFC 4648 §5).
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
