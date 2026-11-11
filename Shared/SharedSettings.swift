import CoreGraphics
import Foundation
import Core

/// Preferences shared by the app (which sets them) and the widget (which reads them).
enum SharedSettings {
    private static var defaults: UserDefaults {
        AppGroup.id.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// Check Spotify every 5 minutes while playing instead of 10. Fresher, but iOS's
    /// daily refresh allowance runs out after fewer listening hours.
    static var responsiveUpdates: Bool {
        get { defaults.bool(forKey: "responsiveUpdates") }
        set { defaults.set(newValue, forKey: "responsiveUpdates") }
    }

    static var plannerSettings: TimelinePlanner.Settings {
        var settings = TimelinePlanner.Settings()
        if responsiveUpdates { settings.playingReload = 5 * 60 }
        return settings
    }
}

/// Colours from a cover image, via a 24 × 24 thumbnail.
enum ArtPaletteExtractor {
    static func palette(from image: CGImage) -> ArtPalette {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? ArtPalette.derive(rgba: pixels, width: side, height: side) : .neutral
    }
}
