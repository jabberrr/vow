import SwiftUI

/// The 150pt sphere: radial gradient (white highlight up-left -> c1 -> c2) with the white glyph inside.
struct OrbBody: View {
    let c1: Color
    let c2: Color
    let glyph: GlyphModel
    /// Glyph rotation in degrees (0 in the active state, slow spin when sealed).
    let glyphAngle: Double

    static let diameter: CGFloat = 150
    static let glyphSize: CGFloat = 84

    private var sphereFill: RadialGradient {
        RadialGradient(
            gradient: Gradient(stops: [
                Gradient.Stop(color: Color.white.opacity(0.9), location: 0.0),
                Gradient.Stop(color: c1, location: 0.2),
                Gradient.Stop(color: c2, location: 0.95)
            ]),
            center: UnitPoint(x: 0.3, y: 0.24),
            startRadius: 0,
            endRadius: 150
        )
    }

    /// Soft darkening toward the lower-right rim for depth.
    private var rimShade: RadialGradient {
        RadialGradient(
            gradient: Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0.3)]),
            center: UnitPoint(x: 0.4, y: 0.36),
            startRadius: 40,
            endRadius: 104
        )
    }

    /// Slight darkening behind the glyph so the white strokes read on any hue.
    private var coreShade: RadialGradient {
        RadialGradient(
            gradient: Gradient(colors: [Color.black.opacity(0.2), Color.black.opacity(0)]),
            center: .center,
            startRadius: 0,
            endRadius: 54
        )
    }

    var body: some View {
        ZStack {
            Circle().fill(sphereFill)
            Circle().fill(rimShade)
            Circle().fill(coreShade)
            Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            GlyphView(model: glyph, lineWidth: 1.8)
                .frame(width: OrbBody.glyphSize, height: OrbBody.glyphSize)
                .rotationEffect(.degrees(glyphAngle))
        }
        .frame(width: OrbBody.diameter, height: OrbBody.diameter)
    }
}

/// A small dot with a static glow built from a radial gradient (no blur).
struct GlowDot: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [color.opacity(0.75), color.opacity(0.22), color.opacity(0)]),
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 2.2
                    )
                )
                .frame(width: size * 4.4, height: size * 4.4)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: size * 0.45, height: size * 0.45)
        }
    }
}
