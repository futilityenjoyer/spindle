import CoreGraphics
import SwiftUI
import WidgetKit
import Core

// Clean glass backgrounds (design/directions.html): a base that is most opaque at the
// edges, with a blurred copy of the album art rising through the middle.
// Keep expressions small and explicitly typed (see the note in VinylRecord.swift).

enum CleanBase {
    /// Smooth silver ("Spindle" widget).
    case silver
    /// A deep colour from the album art ("Spindle Minimal" widget).
    case tinted(RGB)
}

struct CleanBackground: View {
    let art: CGImage?
    let base: CleanBase
    let isSmall: Bool

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            ZStack {
                baseLayer
                if let art {
                    BlurredCover(art: art, width: w, height: h)
                        .mask { coverMask(width: w, height: h) }
                        .opacity(0.9)
                }
                edgeVeil(width: w)
            }
            .frame(width: w, height: h)
        }
    }

    @ViewBuilder
    private var baseLayer: some View {
        switch base {
        case .silver:
            LinearGradient(gradient: CleanBackground.silver, startPoint: .topLeading, endPoint: .bottomTrailing)
        case .tinted(let tone):
            Color(rgb: tone)
        }
    }

    private var edgeColour: Color {
        switch base {
        case .silver: return Color(red: 208 / 255, green: 211 / 255, blue: 216 / 255)
        case .tinted(let tone): return Color(rgb: tone)
        }
    }

    /// Where the blurred cover shows: the middle, fading out toward the edges.
    @ViewBuilder
    private func coverMask(width w: CGFloat, height h: CGFloat) -> some View {
        if isSmall {
            RadialGradient(gradient: CleanBackground.smallMask, center: .center, startRadius: 0, endRadius: w * 0.707)
        } else {
            EllipticalGradient(gradient: CleanBackground.mediumMask, center: .center,
                               startRadiusFraction: 0, endRadiusFraction: 0.5)
                .frame(width: w * 0.92, height: h * 1.56)
                .position(x: w * 0.52, y: h * 0.5)
        }
    }

    /// The base colour laid back over the edges, so they read as solid.
    @ViewBuilder
    private func edgeVeil(width w: CGFloat) -> some View {
        let c: Color = edgeColour
        if isSmall {
            RadialGradient(
                gradient: Gradient(stops: [
                    Gradient.Stop(color: c.opacity(0), location: 0.38),
                    Gradient.Stop(color: c.opacity(0.55), location: 0.62),
                    Gradient.Stop(color: c.opacity(0.95), location: 1.0),
                ]),
                center: .center, startRadius: 0, endRadius: w * 0.707)
        } else {
            LinearGradient(
                gradient: Gradient(stops: [
                    Gradient.Stop(color: c.opacity(0.95), location: 0.0),
                    Gradient.Stop(color: c.opacity(0.35), location: 0.18),
                    Gradient.Stop(color: c.opacity(0), location: 0.34),
                    Gradient.Stop(color: c.opacity(0), location: 0.70),
                    Gradient.Stop(color: c.opacity(0.55), location: 0.88),
                    Gradient.Stop(color: c.opacity(0.9), location: 1.0),
                ]),
                startPoint: .leading, endPoint: .trailing)
        }
    }

    private static let silver = Gradient(stops: [
        Gradient.Stop(color: Color(hex: 0xE4E6E9), location: 0.00),
        Gradient.Stop(color: Color(hex: 0xC3C7CC), location: 0.28),
        Gradient.Stop(color: Color(hex: 0xF3F4F6), location: 0.50),
        Gradient.Stop(color: Color(hex: 0xB9BDC3), location: 0.74),
        Gradient.Stop(color: Color(hex: 0xDCDEE2), location: 1.00),
    ])

    private static let mediumMask = Gradient(stops: [
        Gradient.Stop(color: Color.black, location: 0.0),
        Gradient.Stop(color: Color.black.opacity(0.5), location: 0.5),
        Gradient.Stop(color: Color.black.opacity(0), location: 1.0),
    ])

    private static let smallMask = Gradient(stops: [
        Gradient.Stop(color: Color.black, location: 0.0),
        Gradient.Stop(color: Color.black.opacity(0.5), location: 0.36),
        Gradient.Stop(color: Color.black.opacity(0), location: 0.64),
    ])
}

/// The cover, enlarged and heavily blurred, filling the widget.
struct BlurredCover: View {
    let art: CGImage
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Image(decorative: art, scale: 1)
            .resizable()
            .widgetAccentedRenderingMode(.fullColor)
            .scaledToFill()
            .frame(width: width + 48, height: height + 48)
            .blur(radius: 16, opaque: true)
            .saturation(1.35)
            .frame(width: width, height: height)
            .clipped()
    }
}

/// Text colours for each base.
struct CleanInk {
    let primary: Color
    let secondary: Color

    /// Graphite on silver.
    static let onSilver = CleanInk(
        primary: Color(red: 17 / 255, green: 17 / 255, blue: 19 / 255).opacity(0.92),
        secondary: Color(red: 17 / 255, green: 17 / 255, blue: 19 / 255).opacity(0.58))

    /// White on the album colour.
    static let onTint = CleanInk(primary: Color.white.opacity(0.97), secondary: Color.white.opacity(0.62))
}
