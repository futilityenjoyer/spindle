import CoreGraphics
import SwiftUI

// The record plus the silver tonearm from the Clean glass design (design/directions.html).
// Positions are fractions of a square box so the same drawing fits every widget size.
// Keep expressions small and explicitly typed (see the note in VinylRecord.swift).

struct TurntableLayout {
    /// Record centre, as fractions of the box.
    let center: CGPoint
    /// Record radius ÷ box side.
    let radius: CGFloat
    /// Tonearm pivot, as fractions of the box.
    let pivot: CGPoint

    static let small = TurntableLayout(center: CGPoint(x: 0.46, y: 0.52), radius: 0.40, pivot: CGPoint(x: 0.83, y: 0.17))
    static let medium = TurntableLayout(center: CGPoint(x: 0.46, y: 0.52), radius: 0.44, pivot: CGPoint(x: 0.85, y: 0.16))
}

struct TurntableView<Rotation: ViewModifier>: View {
    let art: CGImage?
    /// On the record while playing; lifted off when paused or stale.
    let armDown: Bool
    /// Light (silver) base vs. dark (album-colour) base: changes the well's shading.
    let onLightBase: Bool
    let layout: TurntableLayout
    let rotation: Rotation

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let side: CGFloat = min(geo.size.width, geo.size.height)
            let diameter: CGFloat = side * layout.radius * 2
            ZStack(alignment: .topLeading) {
                VinylRecord(art: art, rotation: rotation)
                    .frame(width: diameter, height: diameter)
                    .position(x: side * layout.center.x, y: side * layout.center.y)
                Tonearm(armDown: armDown, onLightBase: onLightBase, layout: layout)
                    .frame(width: side, height: side)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Silver tonearm: a dark pivot block sitting in a recessed well, a thin chrome tube with
/// a highlight, and a dark angled headshell; a soft shadow that moves away when it lifts.
/// Light comes from the upper left.
struct Tonearm: View {
    let armDown: Bool
    let onLightBase: Bool
    let layout: TurntableLayout

    var body: some View {
        Canvas { (context: inout GraphicsContext, size: CGSize) in
            Tonearm.draw(in: context, size: size, armDown: armDown, onLightBase: onLightBase, layout: layout)
        }
        .allowsHitTesting(false)
    }

    /// Everything the parts need, computed once.
    private struct Arm {
        let R: CGFloat          // record radius
        let pivot: CGPoint
        let elbow: CGPoint      // where the tube meets the headshell
        let tubeAngle: Double
        let tubeLength: CGFloat
        let tube: CGFloat       // tube thickness
        let headAngle: Double
        let headLength: CGFloat
        let headWidth: CGFloat
    }

    static func draw(in context: GraphicsContext, size: CGSize, armDown: Bool, onLightBase: Bool, layout: TurntableLayout) {
        let side: CGFloat = min(size.width, size.height)
        let R: CGFloat = layout.radius * side
        let center = CGPoint(x: layout.center.x * side, y: layout.center.y * side)
        let pivot = CGPoint(x: layout.pivot.x * side, y: layout.pivot.y * side)

        // The needle rests in the middle of the grooved ring, lower right of the record.
        let target = CGPoint(x: center.x + R * 0.587, y: center.y + R * 0.587)
        let length: CGFloat = hypot(target.x - pivot.x, target.y - pivot.y)
        let playAngle: Double = Double(atan2(target.y - pivot.y, target.x - pivot.x))
        let raised: CGFloat = armDown ? 0 : 1
        let angle: Double = playAngle - Double(raised) * 0.4
        let stylus = CGPoint(x: pivot.x + CGFloat(cos(angle)) * length, y: pivot.y + CGFloat(sin(angle)) * length)

        let headAngle: Double = angle + 0.24
        let headLength: CGFloat = R * 0.21
        let elbow = CGPoint(x: stylus.x - CGFloat(cos(headAngle)) * headLength * 0.82,
                            y: stylus.y - CGFloat(sin(headAngle)) * headLength * 0.82)
        let arm = Arm(
            R: R,
            pivot: pivot,
            elbow: elbow,
            tubeAngle: Double(atan2(elbow.y - pivot.y, elbow.x - pivot.x)),
            tubeLength: hypot(elbow.x - pivot.x, elbow.y - pivot.y),
            tube: R * 0.05,
            headAngle: headAngle,
            headLength: headLength,
            headWidth: R * 0.105)

        let elevation: CGFloat = R * (0.05 + 0.08 * raised)
        let shadowOffset = CGSize(width: elevation * 0.65, height: elevation)

        drawWell(in: context, arm: arm, onLightBase: onLightBase)
        drawCastShadow(in: context, arm: arm, offset: shadowOffset, raised: raised)
        drawTube(in: context, arm: arm)
        drawPivotBlock(in: context, arm: arm)
        drawHeadshell(in: context, arm: arm)
    }

    // MARK: Parts

    /// A recessed circle in the base: the upper-left rim casts a shadow into it,
    /// the lower-right rim catches the light.
    private static func drawWell(in context: GraphicsContext, arm: Arm, onLightBase: Bool) {
        let r: CGFloat = arm.R * 0.27
        let rect = CGRect(x: arm.pivot.x - r, y: arm.pivot.y - r, width: r * 2, height: r * 2)

        var inside = context
        inside.clip(to: Path(ellipseIn: rect))
        inside.fill(Path(rect), with: .color(Color.black.opacity(onLightBase ? 0.06 : 0.22)))

        var innerShadow = inside
        innerShadow.addFilter(.shadow(color: Color.black.opacity(onLightBase ? 0.3 : 0.65),
                                      radius: arm.R * 0.05, x: arm.R * 0.02, y: arm.R * 0.03))
        let ringRect: CGRect = rect.insetBy(dx: -arm.R * 0.03, dy: -arm.R * 0.03)
        innerShadow.stroke(Path(ellipseIn: ringRect), with: .color(.black), lineWidth: arm.R * 0.06)

        let rim: CGFloat = max(1, arm.R * 0.01)
        context.stroke(arc(arm.pivot, r, -0.2, 1.9), with: .color(Color.white.opacity(onLightBase ? 0.75 : 0.14)), lineWidth: rim)
        context.stroke(arc(arm.pivot, r, 2.9, 4.9), with: .color(Color.black.opacity(onLightBase ? 0.14 : 0.55)), lineWidth: rim)
    }

    private static func drawCastShadow(in context: GraphicsContext, arm: Arm, offset: CGSize, raised: CGFloat) {
        var shadow = context
        shadow.addFilter(.blur(radius: max(1, arm.R * (0.025 + 0.035 * raised))))
        shadow.opacity = Double(0.45 - 0.15 * raised)

        var tube = shadow
        tube.translateBy(x: arm.pivot.x + offset.width, y: arm.pivot.y + offset.height)
        tube.rotate(by: .radians(arm.tubeAngle))
        tube.fill(roundedRect(-arm.R * 0.11, -arm.R * 0.08, arm.R * 0.22, arm.R * 0.16, arm.R * 0.025), with: .color(.black))
        tube.fill(roundedRect(-arm.R * 0.1, -arm.tube / 2, arm.tubeLength + arm.R * 0.1, arm.tube, arm.tube / 2), with: .color(.black))

        var head = shadow
        head.translateBy(x: arm.elbow.x + offset.width, y: arm.elbow.y + offset.height)
        head.rotate(by: .radians(arm.headAngle))
        head.fill(roundedRect(-arm.tube * 0.4, -arm.headWidth / 2, arm.headLength, arm.headWidth, arm.R * 0.018), with: .color(.black))
    }

    /// Round chrome tube: dark rim, bright band, darker core, reflected light below.
    private static func drawTube(in context: GraphicsContext, arm: Arm) {
        var tube = context
        tube.translateBy(x: arm.pivot.x, y: arm.pivot.y)
        tube.rotate(by: .radians(arm.tubeAngle))
        let w: CGFloat = arm.tube
        tube.fill(roundedRect(-arm.R * 0.1, -w / 2, arm.tubeLength + arm.R * 0.1, w, w / 2), with: across(chrome, height: w))

        var highlight = Path()
        highlight.move(to: CGPoint(x: arm.R * 0.02, y: -w * 0.18))
        highlight.addLine(to: CGPoint(x: arm.tubeLength - w, y: -w * 0.18))
        tube.stroke(highlight, with: .color(Color.white.opacity(0.85)),
                    style: StrokeStyle(lineWidth: max(w * 0.12, 0.6), lineCap: .round))
    }

    /// Dark rounded block (bearing housing) with visible thickness.
    private static func drawPivotBlock(in context: GraphicsContext, arm: Arm) {
        var block = context
        block.translateBy(x: arm.pivot.x, y: arm.pivot.y)
        block.rotate(by: .radians(arm.tubeAngle))
        let bw: CGFloat = arm.R * 0.22
        let bh: CGFloat = arm.R * 0.16
        let corner: CGFloat = arm.R * 0.025

        var k: CGFloat = arm.R * 0.035
        while k > 0 {
            let off: CGPoint = toLocal(dx: k * 0.6, dy: k, angle: arm.tubeAngle)
            block.fill(roundedRect(-bw / 2 + off.x, -bh / 2 + off.y, bw, bh, corner), with: .color(Color(hex: 0x040405)))
            k -= 0.5
        }
        block.fill(roundedRect(-bw / 2, -bh / 2, bw, bh, corner), with: across(blockFace, height: bh))

        var edge = Path()
        edge.move(to: CGPoint(x: -bw / 2 + corner, y: -bh / 2 + 0.75))
        edge.addLine(to: CGPoint(x: bw / 2 - corner, y: -bh / 2 + 0.75))
        block.stroke(edge, with: .color(Color.white.opacity(0.2)), lineWidth: 1)
    }

    /// Dark angled headshell and cartridge, each with a visible side face.
    private static func drawHeadshell(in context: GraphicsContext, arm: Arm) {
        var head = context
        head.translateBy(x: arm.elbow.x, y: arm.elbow.y)
        head.rotate(by: .radians(arm.headAngle))
        let len: CGFloat = arm.headLength
        let hw: CGFloat = arm.headWidth
        let w: CGFloat = arm.tube
        let corner: CGFloat = arm.R * 0.018
        let side: CGPoint = toLocal(dx: arm.R * 0.028 * 0.6, dy: arm.R * 0.028, angle: arm.headAngle)

        head.fill(roundedRect(-w * 0.4 + side.x, -hw / 2 + side.y, len, hw, corner), with: .color(Color(hex: 0x060607)))
        head.fill(roundedRect(-w * 0.4, -hw / 2, len, hw, corner), with: across(headFace, height: hw))
        head.fill(roundedRect(len * 0.42 + side.x * 0.6, -hw * 0.34 + side.y * 0.6, len * 0.5, hw * 0.68, arm.R * 0.01),
                  with: .color(Color(hex: 0x030304)))
        head.fill(roundedRect(len * 0.42, -hw * 0.34, len * 0.5, hw * 0.68, arm.R * 0.01), with: .color(Color(hex: 0x121214)))

        var edge = Path()
        edge.move(to: CGPoint(x: -w * 0.2, y: -hw / 2 + 0.75))
        edge.addLine(to: CGPoint(x: len * 0.8, y: -hw / 2 + 0.75))
        head.stroke(edge, with: .color(Color.white.opacity(0.3)), lineWidth: 1)
    }

    // MARK: Helpers

    private static let chrome = Gradient(stops: [
        Gradient.Stop(color: Color(hex: 0x2B2D31), location: 0.00),
        Gradient.Stop(color: Color(hex: 0x7E8189), location: 0.16),
        Gradient.Stop(color: Color(hex: 0xFFFFFF), location: 0.30),
        Gradient.Stop(color: Color(hex: 0xD9DBE0), location: 0.40),
        Gradient.Stop(color: Color(hex: 0x6B6E76), location: 0.68),
        Gradient.Stop(color: Color(hex: 0xA3A6AD), location: 0.86),
        Gradient.Stop(color: Color(hex: 0x2E3034), location: 1.00),
    ])

    private static let blockFace = Gradient(stops: [
        Gradient.Stop(color: Color(hex: 0x44454B), location: 0.00),
        Gradient.Stop(color: Color(hex: 0x26272B), location: 0.22),
        Gradient.Stop(color: Color(hex: 0x101012), location: 1.00),
    ])

    private static let headFace = Gradient(stops: [
        Gradient.Stop(color: Color(hex: 0x4A4B51), location: 0.00),
        Gradient.Stop(color: Color(hex: 0x2B2C31), location: 0.30),
        Gradient.Stop(color: Color(hex: 0x16171A), location: 1.00),
    ])

    /// A gradient across a part's width, in the part's own (rotated) coordinates.
    private static func across(_ gradient: Gradient, height: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(gradient, startPoint: CGPoint(x: 0, y: -height / 2), endPoint: CGPoint(x: 0, y: height / 2))
    }

    private static func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
    }

    private static func arc(_ center: CGPoint, _ radius: CGFloat, _ start: Double, _ end: Double) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        return path
    }

    /// A screen-space offset (down-right, away from the light) in a rotated part's coordinates.
    private static func toLocal(dx: CGFloat, dy: CGFloat, angle: Double) -> CGPoint {
        let c: CGFloat = CGFloat(cos(angle))
        let s: CGFloat = CGFloat(sin(angle))
        return CGPoint(x: dx * c + dy * s, y: -dx * s + dy * c)
    }
}
