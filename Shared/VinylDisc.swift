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
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let labelSize = d * VinylStyle.labelFraction
            ZStack {
                // Vinyl body: near-black with a faint lift toward the edge.
                Circle().fill(RadialGradient(
                    colors: [Color(white: 0.05), Color(white: 0.09)],
                    center: .center, startRadius: labelSize / 2, endRadius: d / 2))

                grooves(diameter: d, labelSize: labelSize)

                // Outer rim.
                Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: max(d / 220, 0.5))

                labelView(size: labelSize)

                // Spindle hole.
                Circle()
                    .fill(Color(white: 0.06))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: max(d / 400, 0.4)))
                    .frame(width: d * VinylStyle.spindleFraction, height: d * VinylStyle.spindleFraction)
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Fine concentric grooves, with two slightly wider gaps where tracks would change.
    private func grooves(diameter d: CGFloat, labelSize: CGFloat) -> some View {
        let outer = d * 0.97
        let inner = labelSize + d * 0.03
        let step = (outer - inner) / CGFloat(VinylStyle.grooveCount)
        return ZStack {
            ForEach(0..<VinylStyle.grooveCount, id: \.self) { i in
                let isGap = i == 11 || i == 23
                Circle()
                    .stroke(Color.white.opacity(isGap ? 0.02 : (i.isMultiple(of: 2) ? 0.065 : 0.035)),
                            lineWidth: isGap ? max(step * 0.9, 0.6) : max(d / 500, 0.35))
                    .frame(width: outer - CGFloat(i) * step, height: outer - CGFloat(i) * step)
            }
        }
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
