import CoreGraphics
import SwiftUI
import WidgetKit
import Core

// The record, built from layers per the design spec (§3.2):
//
//   static   grooves, band gaps, run-out, bevel          (rotationally symmetric —
//                                                         rotating them would show nothing)
//   ROTATES  pressing irregularity, run-out etchings,
//            label with printed marks                     (these make the spin visible)
//   static   sheen (the light doesn't turn with the record)
//   static   inscribed cover (kept upright: Spotify's rules forbid animating art)
//
// Note for maintainers: keep expressions small and explicitly typed in this file.
// One long SwiftUI expression here once exceeded the type checker's time limit.

enum VinylLabelStyle {
    /// Plain colour label with printed marks (the Sleeve layout shows the cover separately).
    case plain
    /// The full square cover, upright, inside a label ring in the cover's edge colour.
    case inscribed
}

/// Radii as fractions of the disc radius R (design spec §3.1).
enum VinylGeometry {
    static let programmeEnd: CGFloat = 0.948
    static let runOutWidth: CGFloat = 0.065
    static let leadInGroove: CGFloat = 0.960
    static let bevel: CGFloat = 0.991
    static let bandGaps = 5
    /// Side of an inscribed cover relative to the label diameter (corners touch 94% of the label radius).
    static let inscribedArtFraction: CGFloat = 0.665
}

/// A complete record. `rotation` is applied to the rotating layers only; the widget
/// passes a clock-driven spin, the app passes `EmptyModifier.identity` (still).
struct VinylRecord<Rotation: ViewModifier>: View {
    let style: VinylLabelStyle
    let art: CGImage?
    let palette: ArtPalette
    /// Label diameter ÷ disc diameter.
    let labelFraction: CGFloat
    let rotation: Rotation

    var body: some View {
        ZStack {
            VinylGrooves(labelFraction: labelFraction)
            rotatingLayers.modifier(rotation)
            VinylSheen(labelFraction: labelFraction)
            uprightLayer
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var rotatingLayers: some View {
        ZStack {
            PressingIrregularity(labelFraction: labelFraction)
            RunOutEtchings(labelFraction: labelFraction)
            LabelPrint(colour: labelColour, labelFraction: labelFraction)
        }
    }

    private var labelColour: RGB {
        style == .plain ? palette.label : palette.edge
    }

    @ViewBuilder
    private var uprightLayer: some View {
        if style == .inscribed {
            InscribedCover(art: art, labelFraction: labelFraction)
        } else {
            SpindleHole()
        }
    }
}

// MARK: - Static layers

/// Vinyl body, fine grooves with "loudness" banding, five shinier band gaps,
/// run-out locked groove, lead-in groove and a bevelled edge.
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

        context.fill(ring(radius), with: .color(Color(red: 0.044, green: 0.045, blue: 0.049)))

        let labelRadius: CGFloat = radius * labelFraction
        let programmeStart: CGFloat = labelRadius + radius * VinylGeometry.runOutWidth
        let programmeEnd: CGFloat = radius * VinylGeometry.programmeEnd
        let pitch: CGFloat = max(radius / 68, 0.6)
        let hairline: CGFloat = max(pitch * 0.45, 0.3)
        let gapSpacing: CGFloat = (programmeEnd - programmeStart) / CGFloat(VinylGeometry.bandGaps + 1)

        var r: CGFloat = programmeStart
        var index: Int = 0
        while r < programmeEnd {
            let nearest: CGFloat = ((r - programmeStart) / gapSpacing).rounded()
            let gapCenter: CGFloat = programmeStart + nearest * gapSpacing
            let isGapIndex: Bool = nearest >= 1 && nearest <= CGFloat(VinylGeometry.bandGaps)
            let inGap: Bool = isGapIndex && abs(r - gapCenter) < pitch * 0.8
            if !inGap {
                let phase: Double = Double(index)
                let loudness: Double = 0.5 + 0.5 * sin(phase * 0.71 + 3 * sin(phase * 0.13))
                let alpha: Double = 0.026 + 0.03 * loudness
                context.stroke(ring(r), with: .color(Color.white.opacity(alpha)), lineWidth: hairline)
            }
            r += pitch
            index += 1
        }

        // Band gaps: smooth land between tracks, which catches the light.
        for gap in 1...VinylGeometry.bandGaps {
            let gapRadius: CGFloat = programmeStart + CGFloat(gap) * gapSpacing
            context.stroke(ring(gapRadius), with: .color(Color.white.opacity(0.075)), lineWidth: hairline)
        }

        // Run-out: locked groove, plus a soft shadow where the label begins.
        context.stroke(ring(labelRadius + radius * 0.047), with: .color(Color.white.opacity(0.09)), lineWidth: hairline)
        context.stroke(ring(labelRadius + radius * 0.008), with: .color(Color.black.opacity(0.5)), lineWidth: radius * 0.012)

        // Lead-in guide groove and bevelled edge.
        context.stroke(ring(radius * VinylGeometry.leadInGroove), with: .color(Color.white.opacity(0.06)), lineWidth: hairline)
        context.stroke(ring(radius * VinylGeometry.bevel), with: .color(Color.white.opacity(0.10)), lineWidth: radius * 0.018)
        context.stroke(ring(radius - 0.25), with: .color(Color.white.opacity(0.07)), lineWidth: 0.5)
    }
}

/// Bow-tie highlight from a fixed light, only over the grooved area (never over the label).
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

    /// Two bright lobes on the light axis (upper-left ↔ lower-right), a weak fill light at 90°.
    static let gradient = AngularGradient(
        gradient: Gradient(stops: [
            Gradient.Stop(color: light.opacity(0.30), location: 0.00),
            Gradient.Stop(color: light.opacity(0.08), location: 0.03),
            Gradient.Stop(color: .clear, location: 0.08),
            Gradient.Stop(color: light.opacity(0.05), location: 0.25),
            Gradient.Stop(color: .clear, location: 0.31),
            Gradient.Stop(color: .clear, location: 0.42),
            Gradient.Stop(color: light.opacity(0.08), location: 0.47),
            Gradient.Stop(color: light.opacity(0.30), location: 0.50),
            Gradient.Stop(color: light.opacity(0.08), location: 0.53),
            Gradient.Stop(color: .clear, location: 0.58),
            Gradient.Stop(color: light.opacity(0.05), location: 0.75),
            Gradient.Stop(color: .clear, location: 0.81),
            Gradient.Stop(color: .clear, location: 0.92),
            Gradient.Stop(color: light.opacity(0.08), location: 0.97),
            Gradient.Stop(color: light.opacity(0.30), location: 1.00),
        ]),
        center: .center,
        angle: .degrees(-129))
}

struct SpindleHole: View {
    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let d: CGFloat = min(geo.size.width, geo.size.height)
            let hole: CGFloat = max(d * 0.03, 2)
            Circle()
                .fill(Color(red: 0.044, green: 0.045, blue: 0.049))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                .frame(width: hole, height: hole)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The cover, upright and uncropped, inside the label (Inscribed style).
struct InscribedCover: View {
    let art: CGImage?
    let labelFraction: CGFloat

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let d: CGFloat = min(geo.size.width, geo.size.height)
            let side: CGFloat = d * labelFraction * VinylGeometry.inscribedArtFraction
            CoverArt(art: art, cornerRadius: max(side * 0.06, 2))
                .frame(width: side, height: side)
                .shadow(color: Color.black.opacity(0.25), radius: 1.5, x: 0, y: 0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Album art drawn whole (never cropped), with rounded corners; graphite + ♪ when missing.
struct CoverArt: View {
    let art: CGImage?
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let art {
                Image(decorative: art, scale: 1)
                    .resizable()
                    // Keep album art in full colour on tinted/clear Home Screens (Apple's advice).
                    .widgetAccentedRenderingMode(.fullColor)
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    Color(red: 0.169, green: 0.169, blue: 0.188)
                    Image(systemName: "music.note")
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Rotating layers

/// Faint, uneven angular shading of the grooved area — real pressings aren't perfectly uniform.
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
            Gradient.Stop(color: Color.white.opacity(0.05), location: 0.00),
            Gradient.Stop(color: .clear, location: 0.10),
            Gradient.Stop(color: Color.black.opacity(0.07), location: 0.22),
            Gradient.Stop(color: .clear, location: 0.33),
            Gradient.Stop(color: Color.white.opacity(0.035), location: 0.47),
            Gradient.Stop(color: .clear, location: 0.58),
            Gradient.Stop(color: Color.black.opacity(0.05), location: 0.71),
            Gradient.Stop(color: .clear, location: 0.83),
            Gradient.Stop(color: Color.white.opacity(0.05), location: 1.00),
        ]),
        center: .center)
}

/// Short hand-etched marks in the run-out, like matrix numbers on a real record.
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
        let shading = GraphicsContext.Shading.color(Color.white.opacity(0.22))

        for mark in 0..<9 {
            let start: Double = 0.3 + Double(mark) * 0.09
            var path = Path()
            path.addArc(center: center, radius: etchRadius,
                        startAngle: .radians(start), endAngle: .radians(start + 0.05), clockwise: false)
            context.stroke(path, with: shading, lineWidth: lineWidth)
        }
        var long = Path()
        long.addArc(center: center, radius: etchRadius, startAngle: .radians(3.6), endAngle: .radians(4.3), clockwise: false)
        context.stroke(long, with: .color(Color.white.opacity(0.16)), lineWidth: lineWidth)
    }
}

/// The paper label with a few asymmetric printed marks, so the spin is visible.
struct LabelPrint: View {
    let colour: RGB
    let labelFraction: CGFloat

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let d: CGFloat = min(geo.size.width, geo.size.height)
            let labelSize: CGFloat = d * labelFraction
            let thin: CGFloat = max(labelSize / 120, 0.5)
            let bold: CGFloat = max(labelSize / 45, 1)
            ZStack {
                Circle().fill(Color(rgb: colour))
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: thin)
                    .padding(labelSize * 0.05)
                Circle()
                    .trim(from: 0.04, to: 0.20)
                    .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: bold, lineCap: .round))
                    .padding(labelSize * 0.11)
                Circle()
                    .trim(from: 0.55, to: 0.61)
                    .stroke(Color.black.opacity(0.3), style: StrokeStyle(lineWidth: bold, lineCap: .round))
                    .padding(labelSize * 0.11)
            }
            .frame(width: labelSize, height: labelSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension Color {
    init(rgb: RGB) {
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

/// Muted background and text colours for a palette and appearance (design spec §4.1).
struct WidgetInk {
    let surface: Color
    let primary: Color
    let secondary: Color
    let control: Color

    init(palette: ArtPalette, scheme: ColorScheme) {
        if scheme == .dark {
            surface = Color(rgb: palette.surfaceDark)
            primary = Color.white.opacity(0.95)
            secondary = Color.white.opacity(0.60)
            control = Color.white.opacity(0.14)
        } else {
            let ink = Color(red: 17 / 255, green: 17 / 255, blue: 19 / 255)
            surface = Color(rgb: palette.surfaceLight)
            primary = ink.opacity(0.92)
            secondary = ink.opacity(0.55)
            control = Color.black.opacity(0.07)
        }
    }
}
