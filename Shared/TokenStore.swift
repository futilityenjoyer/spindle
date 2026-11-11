import Foundation
import Core

/// The Spotify token, kept in a protected file in the App Group so the widget can use it.
///
/// - Readable only by this app and its widget (iOS sandbox).
/// - Encrypted at rest; readable after the first unlock since boot, which widgets need.
/// - Excluded from iCloud and computer backups.
enum TokenStore {
    /// The file exists but can't be read yet — typically after a restart, before the
    /// first unlock. This is NOT "signed out": never delete the token or ask the user
    /// to reconnect because of it.
    struct TemporarilyUnavailable: Error {}
    struct NoSharedFolder: Error {}

    private static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("spotify-token.json")
    }

    /// The saved token, or nil if not signed in.
    static func load() throws -> SpotifyToken? {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TemporarilyUnavailable()
        }
        return try? JSONDecoder().decode(SpotifyToken.self, from: data)
    }

    static func save(_ token: SpotifyToken) throws {
        guard var url = fileURL else { throw NoSharedFolder() }
        let data = try JSONEncoder().encode(token)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // An atomic write replaces the file, so set this after every write.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    static func delete() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Lock file serialising token refreshes between the app and the widget.
    static var lockURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("spotify-token.lock")
    }
}

/// An exclusive lock shared by separate processes (app and widget extension), using
/// `flock` on a file in the App Group. Spotify may rotate refresh tokens on every
/// refresh, so two processes refreshing at once could leave one holding a dead token.
enum CrossProcessLock {
    struct Timeout: Error {}
    struct CannotOpen: Error {}

    static func withLock<T>(at url: URL, timeout: TimeInterval = 10,
                            _ body: () async throws -> T) async throws -> T {
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw CannotOpen() }
        defer { _ = close(descriptor) }

        let deadline = Date().addingTimeInterval(timeout)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        defer { _ = flock(descriptor, LOCK_UN) }

        return try await body()
    }
}
