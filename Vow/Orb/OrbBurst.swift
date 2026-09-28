import SwiftUI

/// One particle of the completion explosion. Deterministic per theme seed.
struct BurstParticle {
    let angle: Double
    let distance: Double
    let size: Double
    let life: Double
    let delay: Double
    let color: Color
}

enum BurstParticles {
    static let count: Int = 48

    static func make(theme: DailyTheme) -> [BurstParticle] {
        var rng = Mulberry32(seed: theme.seed ^ 0x5EEDB0B5)
        let palette: [Color] = [theme.c1, theme.c2, Theme.cyan, Theme.pink, Theme.lime, Theme.amber]
        var out: [BurstParticle] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let base: Double = Double(i) / Double(count) * 2 * Double.pi
            let angle: Double = base + rng.range(-0.1, 0.1)
            let distance: Double = rng.range(70, 175)
            let size: Double = rng.range(1.6, 3.6)
            let life: Double = rng.range(0.9, 1.1)
            let delay: Double = rng.range(0, 0.06)
            let index: Int = rng.int(0, palette.count - 1)
            out.append(BurstParticle(
                angle: angle,
                distance: distance,
                size: size,
                life: life,
                delay: delay,
                color: palette[index]
            ))
        }
        return out
    }
}

/// Completion overlay: white core bloom, two staggered shock rings, and ~48 neon particles,
/// all drawn in ONE Canvas inside a TimelineView. Pure function of t = date - completedAt.
/// Layout size is the 220 slot; drawing overflows into a 480pt canvas so particles can fly out.
struct OrbBurst: View {
    let completedAt: Date
    let tint: Color
    let particles: [BurstParticle]

    init(theme: DailyTheme, completedAt: Date) {
        self.completedAt = completedAt
        self.tint = theme.c1
        self.particles = BurstParticles.make(theme: theme)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: false)) { timeline in
            OrbBurstCanvas(
                t: timeline.date.timeIntervalSince(completedAt),
                tint: tint,
                particles: particles
            )
        }
        .frame(width: 220, height: 220)
        .allowsHitTesting(false)
    }
}

struct OrbBurstCanvas: View {
    let t: Double
    let tint: Color
    let particles: [BurstParticle]

    var body: some View {
        Canvas { gc, size in
            OrbBurstRenderer.draw(&gc, size: size, t: t, tint: tint, particles: particles)
        }
        .frame(width: 480, height: 480)
    }
}

enum OrbBurstRenderer {
    static func draw(_ gc: inout GraphicsContext, size: CGSize, t: Double, tint: Color, particles: [BurstParticle]) {
        guard t >= 0, t < OrbTiming.burstDuration else { return }
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        drawBloom(&gc, center: c, t: t, tint: tint)
        drawShockRings(&gc, center: c, t: t, tint: tint)
        for p in particles {
            drawParticle(&gc, center: c, t: t, particle: p)
        }
    }

    static func circle(_ c: CGPoint, _ r: Double) -> Path {
        let rr = CGFloat(max(0, r))
        return Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
    }

    /// White core bloom: grows 50 -> 170pt radius and fades out over 0.55s.
    static func drawBloom(_ gc: inout GraphicsContext, center c: CGPoint, t: Double, tint: Color) {
        let k: Double = t / 0.55
        if k >= 1 { return }
        let r: Double = 50 + 120 * OrbMath.easeOutCubic(k)
        let a: Double = (1 - k) * (1 - k)
        let gradient = Gradient(stops: [
            Gradient.Stop(color: Color.white.opacity(0.95 * a), location: 0.0),
            Gradient.Stop(color: Color.white.opacity(0.55 * a), location: 0.35),
            Gradient.Stop(color: tint.opacity(0.25 * a), location: 0.7),
            Gradient.Stop(color: tint.opacity(0), location: 1.0)
        ])
        gc.fill(
            circle(c, r),
            with: .radialGradient(gradient, center: c, startRadius: 0, endRadius: CGFloat(r))
        )
    }

    /// Two thin shock rings, staggered 0.08s, radius 75 -> 165 (scale 1 -> 2.2), fading out.
    static func drawShockRings(_ gc: inout GraphicsContext, center c: CGPoint, t: Double, tint: Color) {
        for i in 0..<2 {
            let k: Double = (t - 0.08 * Double(i)) / 0.65
            if k < 0 || k >= 1 { continue }
            let r: Double = 75 * (1 + 1.2 * OrbMath.easeOutCubic(k))
            let base: Double = i == 0 ? 0.85 : 0.6
            let alpha: Double = base * (1 - k)
            let width: Double = 0.6 + 2.2 * (1 - k)
            let color: Color = i == 0 ? Color.white : tint
            gc.stroke(circle(c, r), with: .color(color.opacity(alpha)), lineWidth: CGFloat(width))
        }
    }

    /// Glowing particle: halo + glow + body + white core, plus a short motion streak.
    static func drawParticle(_ gc: inout GraphicsContext, center c: CGPoint, t: Double, particle p: BurstParticle) {
        let k: Double = (t - p.delay) / p.life
        if k < 0 || k >= 1 { return }
        let travel: Double = OrbMath.easeOutCubic(k)
        let dist: Double = 62 + p.distance * travel
        let dx: Double = cos(p.angle)
        let dy: Double = sin(p.angle)
        let pos = CGPoint(x: c.x + CGFloat(dx * dist), y: c.y + CGFloat(dy * dist))
        let fade: Double = pow(1 - k, 1.6)
        let r: Double = p.size * (1 - 0.35 * k)

        // Motion streak: length follows the current speed (derivative of the ease-out).
        let speed: Double = 3 * (1 - k) * (1 - k) * p.distance / p.life
        let streak: Double = min(20, speed * 0.035)
        if streak > 0.5 {
            var line = Path()
            line.move(to: pos)
            line.addLine(to: CGPoint(x: pos.x - CGFloat(dx * streak), y: pos.y - CGFloat(dy * streak)))
            gc.stroke(
                line,
                with: .color(p.color.opacity(0.45 * fade)),
                style: StrokeStyle(lineWidth: CGFloat(r * 1.1), lineCap: .round)
            )
        }

        gc.fill(circle(pos, r * 4.0), with: .color(p.color.opacity(0.09 * fade)))
        gc.fill(circle(pos, r * 2.2), with: .color(p.color.opacity(0.26 * fade)))
        gc.fill(circle(pos, r), with: .color(p.color.opacity(0.95 * fade)))
        gc.fill(circle(pos, r * 0.5), with: .color(Color.white.opacity(0.9 * fade)))
    }
}
