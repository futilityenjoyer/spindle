import SwiftUI

/// M0 placeholder record: grooves, a colourful label and an orientation mark, so
/// rotation is easy to see. The real renderer (pre-rendered grooves + full-bleed
/// album art) replaces this in M2. This view never animates itself — the widget
/// applies the rotation, and the app shows it still.
struct VinylDisc: View {
    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(Color(white: 0.07))

                // Grooves: fine concentric rings between the edge and the label.
                ForEach(0..<16, id: \.self) { i in
                    Circle()
                        .stroke(Color.white.opacity(i.isMultiple(of: 3) ? 0.07 : 0.035), lineWidth: max(d / 400, 0.5))
                        .padding(d * (0.035 + CGFloat(i) * 0.018))
                }

                // Label stand-in. A conic gradient makes rotation obvious.
                Circle()
                    .fill(AngularGradient(
                        colors: [Color(red: 0.98, green: 0.55, blue: 0.25),
                                 Color(red: 0.93, green: 0.30, blue: 0.45),
                                 Color(red: 0.45, green: 0.30, blue: 0.85),
                                 Color(red: 0.98, green: 0.55, blue: 0.25)],
                        center: .center))
                    .frame(width: d * 0.38, height: d * 0.38)

                // Orientation mark on the label.
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: d * 0.022, height: d * 0.11)
                    .offset(y: -d * 0.105)

                // Spindle hole.
                Circle()
                    .fill(Color(white: 0.07))
                    .frame(width: d * 0.035, height: d * 0.035)
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Static light reflection laid over the record. Real vinyl's highlights stay
/// fixed while the record turns beneath them, so this never rotates.
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
