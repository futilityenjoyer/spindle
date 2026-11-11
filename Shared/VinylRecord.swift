import CoreGraphics
import SwiftUI
import WidgetKit
import Core

// The matte record from the Clean glass design (design/directions.html).
//
//   static   soft shadow and edge, satin body, grooves, band gaps, bevel, faint sheen,
//            label edge shade, spindle hole   (all rotationally symmetric)
//   ROTATES  pressing irregularity, run-out etchings, the full-bleed cover label
//
// Keep expressions small and explicitly typed in this file: one long SwiftUI
// expression here once exceeded the type checker's time limit on CI.

enum VinylGeometry {
    static let programmeEnd: CGFloat = 0.948
    static let runOutWidth: CGFloat = 0.065
    static let leadInGroove: CGFloat = 0.960
    static let bevel: CGFloat = 0.991
    static let bandGaps = 5
    /// Album-art label diameter ÷ record diameter.
    static let labelFraction: CGFloat = 0.66
}

/// A complete record. `rotation` is applied to the rotating layers only: the widget
/// passes the clock-driven spin, the app passes `EmptyModifier.identity` (still).
struct VinylRecord<Rotation: ViewModifier>: View {
    let art: CGImage?
    let rotation: Rotation
    var labelFraction: CGFloat = VinylGeometry.labelFraction

    var body: some View {
        ZStack {
            RecordBase()
            VinylGrooves(labelFraction: labelFraction)
            rotatingLayers.modifier(rotation)
            VinylSheen(labelFraction: labelFraction)
            LabelFinish(labelFraction: labelFraction)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var rotatingLayers: some View {
        ZStack {
            PressingIrregularity(labelFraction: labelFraction)
            RunOutEtchings(labelFraction: labelFraction)
            FullBleedLabel(art: art, labelFraction: labelFraction)
        }
    }
}

// MARK: - Static layers

/// Soft shadow under the record and a sliver of its edge, so it sits on the surface.
struct RecordBase: View {
    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let d: CGFloat = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(Color.black)
                    .shadow(color: Color.black.opacity(0.35), radius: d * 0.08, x: 0, y: d * 0.025)
                Circle()
                    .fill(Color(red: 0.02, green: 0.02, blue: 0.024))
                    .offset(x: d * 0.006, y: d * 0.011)
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Satin-black body, quiet grooves with "loudness" banding, band gaps, run-out and bevel.
struct VinylGrooves: View {
    let labelFraction: CGFloat

    var body: some View {
        Canvas { (context: inout GraphicsContext, size: CGSize) in
            VinylGrooves.draw(in: &context, size: size, labelFraction: labelFraction)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, labelFraction: CGFloat) {
        let radius: CGFloat = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        func ring(_ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }

        let labelRadius: CGFloat = radius * labelFraction
        let body = Gradient(colors: [Color(red: 0.067, green: 0.067, blue: 0.075),
                                     Color(red: 0.094, green: 0.094, blue: 0.106)])
        context.fill(ring(radius), with: .radialGradient(body, center: center, startRadius: labelRadius, endRadius: radius))

        let programmeStart: CGFloat = labelRadius + radius * VinylGeometry.runOutWidth
        let programmeEnd: CGFloat = radius * VinylGeometry.programmeEnd
        let pitch: CGFloat = max(radius / 70, 0.6)
        let hairline: CGFloat = max(pitch * 0.42, 0.3)
        let gapSpacing: CGFloat = (programmeEnd - programmeStart) / CGFloat(VinylGeometry.bandGaps + 1)

        var r: CGFloat = programmeStart
        var index: Int = 0
        while r < programmeEnd {
            let nearest: CGFloat = ((r - programmeStart) / gapSpacing).rounded()
            let gapCenter: CGFloat = programmeStart + nearest * gapSpacing
            let isGapIndex: Bool = nearest >= 1 && nearest <= CGFloat(VinylGeometry.bandGaps)
            let inGap: Bool = isGapIndex && abs(r - gapCenter) < pitch * 0.9
            if !inGap {
                let phase: Double = Double(index)
                let loudness: Double = 0.5 + 0.5 * sin(phase * 0.71 + 3 * sin(phase * 0.13))
                let alpha: Double = 0.02 + 0.024 * loudness
                context.stroke(ring(r), with: .color(Color.white.opacity(alpha)), lineWidth: hairline)
                context.stroke(ring(r + pitch * 0.5), with: .color(Color.black.opacity(0.18)), lineWidth: pitch * 0.3)
            }
            r += pitch
            index += 1
        }

        for gap in 1...VinylGeometry.bandGaps {
            let gapRadius: CGFloat = programmeStart + CGFloat(gap) * gapSpacing
            context.stroke(ring(gapRadius), with: .color(Color.white.opacity(0.055)), lineWidth: pitch * 0.5)
        }

        context.stroke(ring(labelRadius + radius * 0.047), with: .color(Color.white.opacity(0.09)), lineWidth: hairline)
        context.stroke(ring(labelRadius + radius * 0.008), with: .color(Color.black.opacity(0.55)), lineWidth: radius * 0.014)
        context.stroke(ring(radius * VinylGeometry.leadInGroove), with: .color(Color.white.opacity(0.06)), lineWidth: hairline)
        context.stroke(ring(radius * VinylGeometry.bevel), with: .color(Color.white.opacity(0.07)), lineWidth: radius * 0.014)
        context.stroke(ring(radius - 0.25), with: .color(Color.white.opacity(0.07)), lineWidth: 0.5)
    }
}

/// A faint bow-tie of light on the grooves (never on the label). Kept subtle: the
/// design is matte satin, not gloss.
struct VinylSheen: View {
    let labelFraction: CGFloat

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let d: CGFloat = min(geo.size.width, geo.size.height)
            let band: CGFloat = d / 2 * (1 - labelFraction)
            Circle()
                .fill(VinylSheen.gradient)
                .mask(Circle().strokeBorder(Color.white, lineWidth: band))
                .blendMode(.screen)
                .frame(width: d, height: d)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private static let light = Color(red: 0.93, green: 0.95, blue: 1.0)

    static let gradient = AngularGradient(
        gradient: Gradient(stops: [
            Gradient.Stop(color: light.opacity(0.12), location: 0.00),
            Gradient.Stop(color: light.opacity(0.04), location: 0.03),
            Gradient.Stop(color: .clear, location: 0.08),
            Gradient.Stop(color: light.opacity(0.02), location: 0.25),
            Gradient.Stop(color: .clear, location: 0.31),
            Gradient.Stop(color: .clear, location: 0.42),
            Gradient.Stop(color: light.opacity(0.04), location: 0.47),
            Gradient.Stop(color: light.opacity(0.12), location: 0.50),
            Gradient.Stop(color: light.opacity(0.04), location: 0.53),
            Gradient.Stop(color: .clear, location: 0.58),
            Gradient.Stop(color: light.opacity(0.02), location: 0.75),
            Gradient.Stop(color: .clear, location: 0.81),
            Gradient.Stop(color: .clear, location: 0.92),
            Gradient.Stop(color: light.opacity(0.04), location: 0.97),
            Gradient.Stop(color: light.opacity(0.12), location: 1.00),
        ]),
        center: .center,
        angle: .degrees(-129))
}

/// Soft shadow at the label's edge, a dark rim and the spindle hole (all symmetric).
struct LabelFinish: View {
    let labelFraction: CGFloat

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let d: CGFloat = min(geo.size.width, geo.size.height)
            let size: CGFloat = d * labelFraction
            let hole: CGFloat = max(size * 0.06, 3)
            let rim: CGFloat = max(size * 0.01, 0.5)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.28)],
                                         center: .center, startRadius: size * 0.375, endRadius: size * 0.5))
                    .frame(width: size, height: size)
                Circle()
                    .strokeBorder(Color.black.opacity(0.45), lineWidth: rim)
                    .frame(width: size, height: size)
                Circle()
                    .fill(Color(red: 0.043, green: 0.043, blue: 0.051))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                    .frame(width: hole, height: hole)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Rotating layers

/// The whole cover, cropped to a circle; it turns with the record.
struct FullBleedLabel: View {
    let art: CGImage?
    let labelFraction: CGFloat

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let d: CGFloat = min(geo.size.width, geo.size.height)
            let size: CGFloat = d * labelFraction
            content(size: size)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func content(size: CGFloat) -> some View {
        if let art {
            Image(decorative: art, scale: 1)
                .resizable()
                // Keep album art in full colour on tinted/clear Home Screens.
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFill()
        } else {
            // No artwork (local file, ad, or download failed): a neutral label.
            ZStack {
                Color(red: 0.169, green: 0.169, blue: 0.188)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.28, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
    }
}

/// Faint, uneven shading of the grooved area — real pressings aren't perfectly uniform.
struct PressingIrregularity: View {
    let labelFraction: CGFloat

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let d: CGFloat = min(geo.size.width, geo.size.height)
            let outerInset: CGFloat = d / 2 * (1 - VinylGeometry.programmeEnd)
            let band: CGFloat = d / 2 * (VinylGeometry.programmeEnd - labelFraction - VinylGeometry.runOutWidth)
            Circle()
                .fill(PressingIrregularity.gradient)
                .mask(Circle().strokeBorder(Color.white, lineWidth: max(band, 1)).padding(outerInset))
                .frame(width: d, height: d)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    static let gradient = AngularGradient(
        gradient: Gradient(stops: [
            Gradient.Stop(color: Color.white.opacity(0.04), location: 0.00),
            Gradient.Stop(color: .clear, location: 0.10),
            Gradient.Stop(color: Color.black.opacity(0.06), location: 0.22),
            Gradient.Stop(color: .clear, location: 0.33),
            Gradient.Stop(color: Color.white.opacity(0.03), location: 0.47),
            Gradient.Stop(color: .clear, location: 0.58),
            Gradient.Stop(color: Color.black.opacity(0.05), location: 0.71),
            Gradient.Stop(color: .clear, location: 0.83),
            Gradient.Stop(color: Color.white.opacity(0.04), location: 1.00),
        ]),
        center: .center)
}

/// Short etched marks in the run-out, like matrix numbers on a real record.
struct RunOutEtchings: View {
    let labelFraction: CGFloat

    var body: some View {
        Canvas { (context: inout GraphicsContext, size: CGSize) in
            RunOutEtchings.draw(in: &context, size: size, labelFraction: labelFraction)
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, labelFraction: CGFloat) {
        let radius: CGFloat = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let etchRadius: CGFloat = radius * (labelFraction + 0.033)
        let lineWidth: CGFloat = max(radius * 0.008, 0.5)
        let shading = GraphicsContext.Shading.color(Color.white.opacity(0.2))

        for mark in 0..<9 {
            let start: Double = 0.3 + Double(mark) * 0.09
            var path = Path()
            path.addArc(center: center, radius: etchRadius,
                        startAngle: .radians(start), endAngle: .radians(start + 0.05), clockwise: false)
            context.stroke(path, with: shading, lineWidth: lineWidth)
        }
        var long = Path()
        long.addArc(center: center, radius: etchRadius, startAngle: .radians(3.6), endAngle: .radians(4.3), clockwise: false)
        context.stroke(long, with: .color(Color.white.opacity(0.14)), lineWidth: lineWidth)
    }
}

// MARK: - Colour helpers

extension Color {
    init(rgb: RGB) {
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// 0xRRGGBB
    init(hex: UInt32, opacity: Double = 1) {
        let r: Double = Double((hex >> 16) & 0xFF) / 255
        let g: Double = Double((hex >> 8) & 0xFF) / 255
        let b: Double = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, opacity: opacity)
    }
}
