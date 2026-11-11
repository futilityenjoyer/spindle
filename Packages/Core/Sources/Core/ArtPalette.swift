import Foundation

/// An sRGB colour with components in 0…1.
public struct RGB: Codable, Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// From hue (0…1), saturation and brightness (HSV).
    public init(hue: Double, saturation: Double, brightness: Double) {
        let h: Double = (hue - hue.rounded(.down)) * 6
        let sector: Int = Int(h.rounded(.down)) % 6
        let f: Double = h - h.rounded(.down)
        let v: Double = brightness
        let s: Double = saturation
        let p: Double = v * (1 - s)
        let q: Double = v * (1 - s * f)
        let t: Double = v * (1 - s * (1 - f))
        let rgb: (Double, Double, Double)
        switch sector {
        case 0: rgb = (v, t, p)
        case 1: rgb = (q, v, p)
        case 2: rgb = (p, v, t)
        case 3: rgb = (p, q, v)
        case 4: rgb = (t, p, v)
        default: rgb = (v, p, q)
        }
        self.init(rgb.0, rgb.1, rgb.2)
    }

    /// Hue (0…1), saturation and value.
    public var hsv: (h: Double, s: Double, v: Double) {
        let maxC: Double = max(r, g, b)
        let minC: Double = min(r, g, b)
        let delta: Double = maxC - minC
        var h: Double = 0
        if delta > 0 {
            if maxC == r {
                h = (g - b) / delta
                if h < 0 { h += 6 }
            } else if maxC == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h /= 6
        }
        let s: Double = maxC == 0 ? 0 : delta / maxC
        return (h, s, maxC)
    }
}

/// Colours derived from the album art (design spec §4.1, "tint from art"):
/// a muted background tint, a label colour for the plain record label, and the
/// cover's edge colour for the ring around an inscribed cover.
public struct ArtPalette: Equatable, Sendable {
    public var surfaceDark: RGB
    public var surfaceLight: RGB
    public var label: RGB
    public var edge: RGB
    /// True when the art is (nearly) greyscale or missing, so neutral colours are used.
    public var isNeutral: Bool
    /// A deep colour from the art, used as the base of the "Spindle Minimal" widget
    /// (dark enough for white text).
    public var tone: RGB

    public init(surfaceDark: RGB, surfaceLight: RGB, label: RGB, edge: RGB, isNeutral: Bool,
                tone: RGB = RGB(0.2, 0.2, 0.22)) {
        self.surfaceDark = surfaceDark
        self.surfaceLight = surfaceLight
        self.label = label
        self.edge = edge
        self.isNeutral = isNeutral
        self.tone = tone
    }

    /// Graphite fallback for missing or greyscale art.
    public static let neutral = ArtPalette(
        surfaceDark: RGB(0.106, 0.106, 0.118),
        surfaceLight: RGB(0.957, 0.953, 0.941),
        label: RGB(0.169, 0.169, 0.188),
        edge: RGB(0.169, 0.169, 0.188),
        isNeutral: true)

    /// Derives the palette from a small RGBA8 thumbnail (e.g. 24 × 24) of the cover.
    ///
    /// Colourful mid-tones are weighted up and near-black/near-white pixels down, the
    /// dominant hue is taken from a 24-bin histogram, and the result is muted so text
    /// on the background keeps strong contrast.
    public static func derive(rgba: [UInt8], width: Int, height: Int) -> ArtPalette {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return .neutral }

        let bins = 24
        var weightSum = [Double](repeating: 0, count: bins)
        var saturationSum = [Double](repeating: 0, count: bins)
        var cosSum = [Double](repeating: 0, count: bins)
        var sinSum = [Double](repeating: 0, count: bins)
        var edgeR: Double = 0, edgeG: Double = 0, edgeB: Double = 0, edgeCount: Double = 0

        for y in 0..<height {
            for x in 0..<width {
                let offset: Int = (y * width + x) * 4
                let pixel = RGB(Double(rgba[offset]) / 255, Double(rgba[offset + 1]) / 255, Double(rgba[offset + 2]) / 255)

                if x == 0 || y == 0 || x == width - 1 || y == height - 1 {
                    edgeR += pixel.r
                    edgeG += pixel.g
                    edgeB += pixel.b
                    edgeCount += 1
                }

                let hsv = pixel.hsv
                let weight: Double = pow(hsv.s, 1.4) * (1 - 0.8 * abs(hsv.v - 0.5) / 0.5) + 0.002
                let bin: Int = min(Int(hsv.h * Double(bins)), bins - 1)
                let angle: Double = hsv.h * 2 * Double.pi
                weightSum[bin] += weight
                saturationSum[bin] += hsv.s * weight
                cosSum[bin] += cos(angle) * weight
                sinSum[bin] += sin(angle) * weight
            }
        }

        let edge = edgeCount > 0 ? RGB(edgeR / edgeCount, edgeG / edgeCount, edgeB / edgeCount) : neutral.edge
        guard let best = weightSum.indices.max(by: { weightSum[$0] < weightSum[$1] }), weightSum[best] > 0 else {
            var fallback = neutral
            fallback.edge = edge
            return fallback
        }

        let saturation: Double = saturationSum[best] / weightSum[best]
        var hue: Double = atan2(sinSum[best], cosSum[best]) / (2 * Double.pi)
        if hue < 0 { hue += 1 }

        guard saturation >= 0.12 else {
            var fallback = neutral
            fallback.edge = edge
            return fallback
        }

        return ArtPalette(
            surfaceDark: RGB(hue: hue, saturation: min(saturation * 0.55, 0.45), brightness: 0.20),
            surfaceLight: RGB(hue: hue, saturation: min(saturation * 0.22, 0.12), brightness: 0.95),
            label: RGB(hue: hue, saturation: min(max(saturation * 0.85, 0.35), 0.75), brightness: 0.62),
            edge: edge,
            isNeutral: false,
            tone: RGB(hue: hue, saturation: min(max(saturation * 0.8, 0.35), 0.7), brightness: 0.36))
    }
}
