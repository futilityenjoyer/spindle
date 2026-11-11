import CoreGraphics
import SwiftUI
import WidgetKit

/// Proportions of the record, relative to its diameter.
enum VinylStyle {
    /// Album art label. Real records use ~33%; we go big so the art is the focal point.
    static let labelFraction: CGFloat = 0.60
    static let spindleFraction: CGFloat = 0.028
    static let grooveCount = 34
}

/// The record: grooves, a full-bleed circular album-art label and a spindle hole.
/// It never animates itself — the widget applies the rotation and the app shows it still.
/// Grooves are rotationally symmetric, so rotating the whole disc looks the same as
/// rotating only the label, and is cheaper to describe.
struct VinylDisc: View {
    var label: CGImage? = nil

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let d: CGFloat = min(geo.size.width, geo.size.height)
            let labelSize: CGFloat = d * VinylStyle.labelFraction
            let rimWidth: CGFloat = max(d / 220, 0.5)
            let spindleSize: CGFloat = d * VinylStyle.spindleFraction
            let spindleRim: CGFloat = max(d / 400, 0.4)
            ZStack {
                // Vinyl body: near-black with a faint lift toward the edge.
                Circle().fill(RadialGradient(
                    colors: [Color(white: 0.05), Color(white: 0.09)],
                    center: .center, startRadius: labelSize / 2, endRadius: d / 2))

                grooves(diameter: d, labelSize: labelSize)

                // Outer rim.
                Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: rimWidth)

                labelView(size: labelSize)

                // Spindle hole.
                Circle()
                    .fill(Color(white: 0.06))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: spindleRim))
                    .frame(width: spindleSize, height: spindleSize)
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Fine concentric grooves, with two slightly wider gaps where tracks would change.
    // Kept as small, explicitly typed steps: one combined expression here was too
    // complex for the Swift type checker (CI build failure, 2026-11-12).
    private func grooves(diameter d: CGFloat, labelSize: CGFloat) -> some View {
        let outer: CGFloat = d * 0.97
        let inner: CGFloat = labelSize + d * 0.03
        let step: CGFloat = (outer - inner) / CGFloat(VinylStyle.grooveCount)
        let fineWidth: CGFloat = max(d / 500, 0.35)
        let gapWidth: CGFloat = max(step * 0.9, 0.6)
        return ZStack {
            ForEach(0..<VinylStyle.grooveCount, id: \.self) { (i: Int) in
                GrooveRing(
                    diameter: outer - CGFloat(i) * step,
                    opacity: Self.grooveOpacity(i),
                    lineWidth: Self.isGap(i) ? gapWidth : fineWidth)
            }
        }
    }

    /// Two wider, fainter rings where tracks would change on a real record.
    private static func isGap(_ i: Int) -> Bool {
        i == 11 || i == 23
    }

    private static func grooveOpacity(_ i: Int) -> Double {
        if isGap(i) { return 0.02 }
        return i.isMultiple(of: 2) ? 0.065 : 0.035
    }

    @ViewBuilder
    private func labelView(size: CGFloat) -> some View {
        Group {
            if let label {
                Image(decorative: label, scale: 1)
                    .resizable()
                    // Keep album art in full colour on tinted/clear Home Screens
                    // (Apple recommends this for album art). No effect outside widgets.
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
            } else {
                // No artwork (local file, ad, or download failed): a neutral label.
                ZStack {
                    LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.28, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: max(size / 160, 0.5)))
    }
}

/// One groove ring.
private struct GrooveRing: View {
    let diameter: CGFloat
    let opacity: Double
    let lineWidth: CGFloat

    var body: some View {
        Circle()
            .stroke(Color.white.opacity(opacity), lineWidth: lineWidth)
            .frame(width: diameter, height: diameter)
    }
}

/// Static light reflection over the record. Real vinyl's highlights stay put while
/// the record turns beneath them, so this layer never rotates.
struct VinylSheen: View {
    var body: some View {
        Circle()
            .fill(AngularGradient(
                gradient: Gradient(colors: [.clear, .white.opacity(0.10), .clear, .clear,
                                            .white.opacity(0.06), .clear, .clear]),
                center: .center,
                angle: .degrees(-30)))
            .blendMode(.screen)
            .aspectRatio(1, contentMode: .fit)
            .allowsHitTesting(false)
    }
}
