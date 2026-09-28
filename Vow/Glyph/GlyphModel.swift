import Foundation
import CoreGraphics

struct GlyphEdge: Equatable, Hashable {
    let a: Int
    let b: Int
}

/// A small constellation in unit space (centered at 0,0, radius ~1).
struct GlyphModel: Equatable {
    let points: [CGPoint]
    let edges: [GlyphEdge]
    let hasCenterDot: Bool

    private static let cacheLock = NSLock()
    private static var cache: [UInt32: GlyphModel] = [:]

    static func cached(seed: UInt32) -> GlyphModel {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let hit = cache[seed] {
            return hit
        }
        let model = GlyphModel.generate(seed: seed)
        cache[seed] = model
        return model
    }

    /// Deterministic generation. Draw order: n, start angle, (jitter, radius) per point,
    /// chord count, chord picks, center dot.
    static func generate(seed: UInt32) -> GlyphModel {
        var rng = Mulberry32(seed: seed ^ 0x9E3779B9)
        let n: Int = rng.int(5, 8)
        let step: Double = (2.0 * Double.pi) / Double(n)
        let start: Double = rng.next() * 2.0 * Double.pi

        var points: [CGPoint] = []
        for i in 0..<n {
            let jitter: Double = rng.range(-0.25, 0.25) * step
            let angle: Double = start + Double(i) * step + jitter
            let radius: Double = rng.range(0.55, 1.0)
            points.append(CGPoint(x: cos(angle) * radius, y: sin(angle) * radius))
        }

        var edges: [GlyphEdge] = []
        for i in 0..<n {
            edges.append(GlyphEdge(a: i, b: (i + 1) % n))
        }

        // Non-adjacent pairs (a < b), excluding the ring's closing pair (0, n-1).
        var candidates: [GlyphEdge] = []
        for a in 0..<n {
            var b: Int = a + 2
            while b < n {
                if !(a == 0 && b == n - 1) {
                    candidates.append(GlyphEdge(a: a, b: b))
                }
                b += 1
            }
        }

        let chordCount: Int = rng.int(1, 3)
        var added: Int = 0
        while added < chordCount && !candidates.isEmpty {
            let idx: Int = rng.int(0, candidates.count - 1)
            edges.append(candidates.remove(at: idx))
            added += 1
        }

        let centerDot: Bool = rng.next() < 0.5
        return GlyphModel(points: points, edges: edges, hasCenterDot: centerDot)
    }
}
