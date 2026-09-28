import SwiftUI

/// 160pt progress ring hugging the 150pt orb. Trim 0...progress, starts at 12 o'clock,
/// with a white comet head at the leading edge.
struct OrbRing: View {
    let progress: Double
    let headOpacity: Double
    let c1: Color
    let c2: Color

    static let diameter: CGFloat = 160
    static let lineWidth: CGFloat = 5

    /// Tail fades in from transparent, then c1 -> c2 -> c1. No white stop.
    /// The gradient is offset by -4 degrees so the round cap of the tail (which pokes slightly
    /// behind the ring start) samples the transparent end instead of wrapping to c1.
    private var gradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                Gradient.Stop(color: c1.opacity(0), location: 0.0),
                Gradient.Stop(color: c1, location: 0.12),
                Gradient.Stop(color: c2, location: 0.55),
                Gradient.Stop(color: c1, location: 1.0)
            ]),
            center: .center,
            startAngle: .degrees(-4),
            endAngle: .degrees(356)
        )
    }

    var body: some View {
        let p: Double = OrbMath.clamp01(progress)
        let angle: Double = p * 2 * Double.pi - Double.pi / 2
        let r: Double = Double(OrbRing.diameter) / 2
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: OrbRing.lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(p))
                .stroke(gradient, style: StrokeStyle(lineWidth: OrbRing.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CometHead()
                .offset(x: CGFloat(r * cos(angle)), y: CGFloat(r * sin(angle)))
                .opacity(headOpacity)
        }
        .frame(width: OrbRing.diameter, height: OrbRing.diameter)
    }
}

/// White dot with a static radial-gradient glow (no blur, no shadow).
struct CometHead: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.8),
                            Color.white.opacity(0.22),
                            Color.white.opacity(0)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 13
                    )
                )
                .frame(width: 26, height: 26)
            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
        }
    }
}
