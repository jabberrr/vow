import SwiftUI

/// Layered radial-gradient glow behind the orb (c1 / c2 / soft white). No blur.
/// Only its opacity and scale change per frame.
struct OrbAura: View {
    let c1: Color
    let c2: Color
    let intensity: Double
    let scale: CGFloat

    private var outer: RadialGradient {
        RadialGradient(
            gradient: Gradient(colors: [c1.opacity(0.5), c1.opacity(0.16), c1.opacity(0)]),
            center: .center,
            startRadius: 0,
            endRadius: 150
        )
    }

    private var accent: RadialGradient {
        RadialGradient(
            gradient: Gradient(colors: [c2.opacity(0.45), c2.opacity(0.12), c2.opacity(0)]),
            center: .center,
            startRadius: 0,
            endRadius: 115
        )
    }

    private var core: RadialGradient {
        RadialGradient(
            gradient: Gradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)]),
            center: .center,
            startRadius: 40,
            endRadius: 100
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(outer)
                .frame(width: 300, height: 300)
            Circle()
                .fill(accent)
                .frame(width: 230, height: 230)
                .offset(x: 12, y: 14)
            Circle()
                .fill(core)
                .frame(width: 200, height: 200)
        }
        .frame(width: 220, height: 220)
        .scaleEffect(scale)
        .opacity(OrbMath.clamp01(intensity))
        .allowsHitTesting(false)
    }
}
