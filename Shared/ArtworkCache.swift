import CoreGraphics
import Foundation
import ImageIO
import Core

/// Album art on disk in the App Group, shared by the app and the widget.
///
/// Battery and memory rules (FEASIBILITY §4.5): each cover is downloaded once from
/// Spotify's CDN (the ~300 px size), decoded straight to the pixel size we draw
/// with ImageIO (never the full image), and evicted after 7 days or past 25 MB.
enum ArtworkCache {
    /// Spotify offers 64, 300 and 640 px covers; 300 px is plenty for a widget label.
    static let sourceMinWidth = 300
    private static let maxAge: TimeInterval = 7 * 24 * 3600
    private static let maxBytes = 25 * 1024 * 1024

    static func remoteURL(for item: PlayableItem) -> URL? {
        item.image(minWidth: sourceMinWidth).flatMap { URL(string: $0.url) }
    }

    /// Downloads missing covers (in parallel, one burst) when `download` is true, then
    /// returns images decoded at `maxPixelSize`, keyed by their remote URL.
    static func images(for items: [PlayableItem], maxPixelSize: Int, download: Bool = true) async -> [URL: CGImage] {
        let remotes = Array(Set(items.compactMap { remoteURL(for: $0) }))
        if download {
            await withTaskGroup(of: Void.self) { group in
                for remote in remotes {
                    group.addTask { await fetchIfMissing(remote) }
                }
            }
        }
        var result: [URL: CGImage] = [:]
        for remote in remotes {
            guard let file = fileURL(for: remote), let image = thumbnail(at: file, maxPixelSize: maxPixelSize) else { continue }
            result[remote] = image
            touch(file)
        }
        if download { prune() }
        return result
    }

    /// Removes all cached covers (on sign-out).
    static func purge() {
        guard let directory = directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Private

    private static var directory: URL? {
        guard let base = AppGroup.containerURL else { return nil }
        let directory = base.appendingPathComponent("artwork", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Spotify image URLs end in a unique image ID, which makes a good file name.
    private static func fileURL(for remote: URL) -> URL? {
        let name = remote.lastPathComponent.filter { $0.isLetter || $0.isNumber }
        guard !name.isEmpty else { return nil }
        return directory?.appendingPathComponent(name + ".img")
    }

    private static func fetchIfMissing(_ remote: URL) async {
        guard let file = fileURL(for: remote), !FileManager.default.fileExists(atPath: file.path) else { return }
        let request = URLRequest(url: remote, timeoutInterval: SpotifyAPI.timeout)
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              result.0.count < 2_000_000
        else { return }   // a missing cover just shows the neutral label
        try? result.0.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Decodes only as many pixels as we draw.
    private static func thumbnail(at file: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Marks a cover as recently used, for eviction order.
    private static func touch(_ file: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    }

    /// Deletes covers unused for 7 days, then the oldest until under 25 MB.
    private static func prune() {
        guard let directory = directory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        else { return }

        let now = Date()
        var kept: [(url: URL, date: Date, size: Int)] = []
        for file in files {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let date = values?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(date) > maxAge {
                try? FileManager.default.removeItem(at: file)
            } else {
                kept.append((file, date, values?.fileSize ?? 0))
            }
        }

        var total = kept.reduce(0) { $0 + $1.size }
        for file in kept.sorted(by: { $0.date < $1.date }) where total > maxBytes {
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
    }
}
