import SwiftUI

/// The holdable orb. Everything visual is computed from `timeline.date` and the immutable
/// `phase` snapshot; the TimelineView body never writes state or triggers side effects.
struct ActiveOrb: View {
    let theme: DailyTheme
    let phase: OrbPhase

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: false)) { timeline in
            ActiveOrbFrame(theme: theme, phase: phase, date: timeline.date)
        }
        .frame(width: 220, height: 220)
    }
}

/// One rendered frame of the active orb (pure function of theme, phase, date).
struct ActiveOrbFrame: View {
    let theme: DailyTheme
    let phase: OrbPhase
    let date: Date

    var body: some View {
        let p: Double = phase.progress(at: date)
        let breath: Double = OrbMath.breath(date)
        let groupScale: Double = OrbMath.groupScale(phase: phase, date: date)
        let dashAngle: Double = OrbMath.loop(date, period: 40) * 360
        let dotsAngle: Double = OrbMath.loop(date, period: 7) * 2 * Double.pi
        ZStack {
            OrbAura(
                c1: theme.c1,
                c2: theme.c2,
                intensity: 0.55 + 0.1 * breath + 0.35 * p,
                scale: CGFloat(0.97 + 0.04 * breath + 0.05 * p)
            )
            DashedOrbit(angle: dashAngle)
            OrbitDots(angle: dotsAngle, opacity: p, colors: [theme.c1, theme.c2, Color.white])
            ZStack {
                OrbBody(c1: theme.c1, c2: theme.c2, glyph: theme.glyph, glyphAngle: 0)
                OrbRing(progress: p, headOpacity: phase.headOpacity(at: date), c1: theme.c1, c2: theme.c2)
            }
            .scaleEffect(CGFloat(groupScale))
        }
        .frame(width: 220, height: 220)
    }
}

/// Slow dashed outer ring (~196pt), one revolution per 40s.
struct DashedOrbit: View {
    let angle: Double

    var body: some View {
        Circle()
            .stroke(
                Color.white.opacity(0.18),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 7])
            )
            .frame(width: 196, height: 196)
            .rotationEffect(.degrees(angle))
    }
}

/// Three glowing dots orbiting on a 104pt radius; fade in with hold progress.
struct OrbitDots: View {
    let angle: Double
    let opacity: Double
    let colors: [Color]

    static let radius: Double = 104

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                dot(i)
            }
        }
        .frame(width: 220, height: 220)
        .opacity(OrbMath.clamp01(opacity))
    }

    private func dot(_ i: Int) -> some View {
        let a: Double = angle + Double(i) * 2 * Double.pi / 3
        let color: Color = colors.isEmpty ? Color.white : colors[i % colors.count]
        return GlowDot(color: color, size: 4.5)
            .offset(x: CGFloat(OrbitDots.radius * cos(a)), y: CGFloat(OrbitDots.radius * sin(a)))
    }
}
