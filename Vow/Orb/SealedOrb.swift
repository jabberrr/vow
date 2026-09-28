import SwiftUI

/// Sealed state: slowly rotating glyph, pulsing aura, rainbow orbit ring, three satellites.
/// Same 220pt slot and same centre as the active orb.
struct SealedOrb: View {
    let theme: DailyTheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            SealedOrbFrame(theme: theme, date: timeline.date)
        }
        .frame(width: 220, height: 220)
    }
}

struct SealedOrbFrame: View {
    let theme: DailyTheme
    let date: Date

    var body: some View {
        let pulse: Double = OrbMath.wave(date, period: 4.2)
        let breath: Double = OrbMath.breath(date)
        let glyphAngle: Double = OrbMath.loop(date, period: 60) * 360
        let rainbowAngle: Double = OrbMath.loop(date, period: 30) * 360
        ZStack {
            OrbAura(
                c1: theme.c1,
                c2: theme.c2,
                intensity: 0.6 + 0.32 * pulse,
                scale: CGFloat(0.95 + 0.09 * pulse)
            )
            RainbowOrbit(angle: rainbowAngle)
            SealedSatellites(date: date, c1: theme.c1, c2: theme.c2)
            ZStack {
                OrbBody(c1: theme.c1, c2: theme.c2, glyph: theme.glyph, glyphAngle: glyphAngle)
                SealedRing(c1: theme.c1, c2: theme.c2)
            }
            .scaleEffect(CGFloat(1 + 0.035 * breath))
        }
        .frame(width: 220, height: 220)
    }
}

/// Full ring hugging the orb (continuity with the completed progress ring).
struct SealedRing: View {
    let c1: Color
    let c2: Color

    var body: some View {
        Circle()
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [c1, c2, c1]),
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                lineWidth: OrbRing.lineWidth
            )
            .rotationEffect(.degrees(-90))
            .opacity(0.9)
            .frame(width: OrbRing.diameter, height: OrbRing.diameter)
    }
}

/// Thin multi-hue orbit ring (~182pt), slowly rotating.
struct RainbowOrbit: View {
    let angle: Double

    static let hues: [Color] = {
        var colors: [Color] = []
        for i in 0...8 {
            colors.append(Color(hue: Double(i) / 8.0, saturation: 0.7, brightness: 1.0))
        }
        return colors
    }()

    var body: some View {
        Circle()
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: RainbowOrbit.hues),
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                lineWidth: 1.5
            )
            .frame(width: 182, height: 182)
            .rotationEffect(.degrees(angle))
            .opacity(0.75)
    }
}

/// Three small glowing satellites orbiting at different radii and speeds.
struct SealedSatellites: View {
    let date: Date
    let c1: Color
    let c2: Color

    var body: some View {
        ZStack {
            satellite(radius: 91, period: 7, phase: 0.0, color: c1, size: 5)
            satellite(radius: 100, period: 11, phase: 0.33, color: c2, size: 4)
            satellite(radius: 108, period: -16, phase: 0.66, color: Color.white, size: 3.5)
        }
        .frame(width: 220, height: 220)
    }

    private func satellite(radius: Double, period: Double, phase: Double, color: Color, size: CGFloat) -> some View {
        let turn: Double = OrbMath.loop(date, period: abs(period))
        let signed: Double = period < 0 ? -turn : turn
        let a: Double = (signed + phase) * 2 * Double.pi - Double.pi / 2
        return GlowDot(color: color, size: size)
            .offset(x: CGFloat(radius * cos(a)), y: CGFloat(radius * sin(a)))
    }
}
