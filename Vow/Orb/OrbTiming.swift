import Foundation

/// Timing constants for the orb. `hold` is THE single hold constant: it drives the ring fill,
/// the completion DispatchWorkItem, and the length of the buildup sound.
enum OrbTiming {
    static let hold: Double = 1.4

    /// Delay from completion to `onSealed()`.
    static let sealDelay: Double = 0.9
    /// How long an early release takes to drain the ring back to empty.
    static let releaseDecay: Double = 0.35
    /// Length of the completion pop (scale settles back to 1.0 by then).
    static let popDuration: Double = 0.6
    /// How long the burst overlay (bloom, shock rings, particles) stays mounted after completion.
    static let burstDuration: Double = 1.3
    /// Idle breathing period.
    static let breathPeriod: Double = 3.2
    /// Crossfade from the burst/active orb into the sealed orb.
    static let sealCrossfade: Double = 0.6
}

/// Pure math helpers. Everything visual is a function of time; nothing here has side effects.
enum OrbMath {
    static func clamp01(_ x: Double) -> Double {
        if x < 0 { return 0 }
        if x > 1 { return 1 }
        return x
    }

    static func easeOutCubic(_ x: Double) -> Double {
        let k: Double = 1 - clamp01(x)
        return 1 - k * k * k
    }

    static func easeOutQuad(_ x: Double) -> Double {
        let k: Double = 1 - clamp01(x)
        return 1 - k * k
    }

    /// Phase in [0, 1) of a loop with the given period, driven by wall-clock time.
    static func loop(_ date: Date, period: Double) -> Double {
        let s: Double = date.timeIntervalSinceReferenceDate
        let r: Double = s.truncatingRemainder(dividingBy: period)
        let v: Double = r / period
        return v < 0 ? v + 1 : v
    }

    /// Smooth 0...1...0 wave with the given period.
    static func wave(_ date: Date, period: Double) -> Double {
        let ph: Double = loop(date, period: period)
        return 0.5 * (1 - cos(ph * 2 * Double.pi))
    }

    /// Breathing amount 0...1 (multiply by the breathing depth).
    static func breath(_ date: Date) -> Double {
        return wave(date, period: OrbTiming.breathPeriod)
    }

    /// Squeeze applied to the orb group while charging (1.0 at rest, 0.96 at full charge).
    static func chargeSqueeze(_ progress: Double) -> Double {
        return 1 - 0.04 * clamp01(progress)
    }

    /// Completion pop scale as a pure function of seconds since completion.
    /// Rises from the charged squeeze (0.96) to 1.25 in 0.12s, then a critically-shaped
    /// damped spring back to 1.0 (settled by `OrbTiming.popDuration`).
    static func popScale(_ t: Double) -> Double {
        let start: Double = chargeSqueeze(1)
        let peak: Double = 1.25
        let rise: Double = 0.12
        if t <= 0 { return start }
        if t < rise {
            return start + (peak - start) * easeOutQuad(t / rise)
        }
        if t >= OrbTiming.popDuration { return 1 }
        let u: Double = t - rise
        let k: Double = 10
        let w: Double = 16
        // x(0) = 1, x'(0) = 0, decays with small undershoot.
        let x: Double = exp(-k * u) * (cos(w * u) + (k / w) * sin(w * u))
        return 1 + (peak - 1) * x
    }

    /// Scale of the orb + ring group in the active state.
    static func groupScale(phase: OrbPhase, date: Date) -> Double {
        let breathe: Double = 1 + 0.035 * breath(date)
        if let done = phase.completedAt {
            return breathe * popScale(date.timeIntervalSince(done))
        }
        return breathe * chargeSqueeze(phase.progress(at: date))
    }
}

/// Immutable snapshot of the hold interaction. The controller replaces it on discrete
/// events (press, release, completion); views only read it.
struct OrbPhase: Equatable {
    var pressStart: Date? = nil
    var releasedAt: Date? = nil
    var progressAtRelease: Double = 0
    var completedAt: Date? = nil

    /// PURE ring progress 0...1 at `date`.
    func progress(at date: Date) -> Double {
        if completedAt != nil { return 1 }
        if let start = pressStart {
            return OrbMath.clamp01(date.timeIntervalSince(start) / OrbTiming.hold)
        }
        if let released = releasedAt {
            let k: Double = OrbMath.clamp01(date.timeIntervalSince(released) / OrbTiming.releaseDecay)
            let remain: Double = 1 - k
            return progressAtRelease * remain * remain * remain
        }
        return 0
    }

    /// Opacity of the comet head: visible while there is progress, fades out after completion.
    func headOpacity(at date: Date) -> Double {
        if let done = completedAt {
            return 1 - OrbMath.clamp01(date.timeIntervalSince(done) / 0.4)
        }
        return progress(at: date) > 0.004 ? 1 : 0
    }
}
