import SwiftUI

/// 32-bit FNV-1a over the UTF-8 bytes of a string (wrapping arithmetic).
enum FNV1a {
    static func hash(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for byte in s.utf8 {
            h ^= UInt32(byte)
            h = h &* 16777619
        }
        return h
    }
}

/// Exact port of the JS `mulberry32` PRNG. All ops are wrapping.
struct Mulberry32 {
    private(set) var state: UInt32

    init(seed: UInt32) {
        self.state = seed
    }

    mutating func nextUInt32() -> UInt32 {
        state = state &+ 0x6D2B79F5
        var t: UInt32 = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return t ^ (t >> 14)
    }

    /// Uniform in [0, 1).
    mutating func next() -> Double {
        return Double(nextUInt32()) / 4294967296.0
    }

    /// Uniform in [lo, hi).
    mutating func range(_ lo: Double, _ hi: Double) -> Double {
        return lo + (hi - lo) * next()
    }

    /// Uniform integer in lo...hi (inclusive). Always consumes one draw.
    mutating func int(_ lo: Int, _ hi: Int) -> Int {
        let r: Double = next()
        if hi <= lo { return lo }
        let span: Int = hi - lo + 1
        let v: Int = lo + Int(r * Double(span))
        return min(v, hi)
    }
}

/// Everything that is deterministic for a given (cycle, day).
struct DailyTheme: Equatable {
    let cycle: Int
    let day: Int
    let seed: UInt32
    let h1: Double
    let h2: Double
    let c1: Color
    let c2: Color
    let glyph: GlyphModel
    let glyphNumber: Int
    let creed: String

    static func make(cycle: Int, day: Int) -> DailyTheme {
        let seed: UInt32 = FNV1a.hash("vow|\(cycle)|\(day)")
        var rng = Mulberry32(seed: seed)
        let h1: Double = rng.next() * 360.0
        let h2: Double = (h1 + rng.range(90, 210)).truncatingRemainder(dividingBy: 360.0)
        let number: Int = (cycle - 1) * 30 + day
        return DailyTheme(
            cycle: cycle,
            day: day,
            seed: seed,
            h1: h1,
            h2: h2,
            c1: Color(hue: h1 / 360.0, saturation: 0.85, brightness: 1.0),
            c2: Color(hue: h2 / 360.0, saturation: 0.85, brightness: 1.0),
            glyph: GlyphModel.cached(seed: seed),
            glyphNumber: number,
            creed: Creeds.line(for: number)
        )
    }
}
