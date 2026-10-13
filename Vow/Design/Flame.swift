import SwiftUI

enum FlameSize: Equatable {
    case small
    case medium
    /// Stage, regular screens (46 / 34 pt, scaled).
    case large
    /// Stage, compact screens (38 / 28 pt, scaled).
    case largeCompact
}

/// Flame + count. Bright when count > 0, grey at 0. `flareToken` increments trigger a flare.
struct FlameStreak: View {
    let count: Int
    let size: FlameSize
    let flareToken: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var largeNumber: CGFloat = 46
    @ScaledMetric(relativeTo: .largeTitle) private var largeIcon: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var compactNumber: CGFloat = 38
    @ScaledMetric(relativeTo: .largeTitle) private var compactIcon: CGFloat = 28
    @State private var flaring: Bool = false

    init(count: Int, size: FlameSize, flareToken: Int = 0) {
        self.count = count
        self.size = size
        self.flareToken = flareToken
    }

    private var lit: Bool {
        count > 0
    }

    private var iconSize: CGFloat {
        switch size {
        case .small: return 13
        case .medium: return 17
        case .large: return largeIcon
        case .largeCompact: return compactIcon
        }
    }

    private var numberFont: Font {
        switch size {
        case .small: return Fonts.numberSmall
        case .medium: return Fonts.numberMedium
        case .large: return Font.system(size: largeNumber, weight: .heavy, design: .rounded)
        case .largeCompact: return Font.system(size: compactNumber, weight: .heavy, design: .rounded)
        }
    }

    private var spacing: CGFloat {
        switch size {
        case .small: return 2
        case .medium: return 3
        case .large, .largeCompact: return 4
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            icon
            Text("\(count)")
                .font(numberFont)
                .monospacedDigit()
                .foregroundStyle(lit ? Ink.flame : Ink.text3)
                .rollingNumber(Double(count))
        }
        .onChange(of: flareToken) { _, newValue in
            if newValue > 0 {
                flare()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "1-day streak" : "\(count)-day streak")
    }

    private var icon: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(iconStyle)
            .scaleEffect(flaring && !reduceMotion ? 1.28 : 1)
            .background(glow)
    }

    private var iconStyle: AnyShapeStyle {
        lit ? AnyShapeStyle(Ink.flameGradient) : AnyShapeStyle(Ink.text3.opacity(0.6))
    }

    private var glow: some View {
        Circle()
            .fill(RadialGradient(
                gradient: Gradient(colors: [Ink.flame.opacity(0.55), Ink.flame.opacity(0)]),
                center: .center,
                startRadius: 0,
                endRadius: iconSize * 1.6))
            .frame(width: iconSize * 3.2, height: iconSize * 3.2)
            .opacity(flaring ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func flare() {
        withAnimation(reduceMotion ? Anim.fade : Anim.flareUp) {
            flaring = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Anim.flareHoldNanos)
            withAnimation(reduceMotion ? Anim.fade : Anim.flareDown) {
                flaring = false
            }
        }
    }
}

/// 12 embers from the centre over 0.8 s each time `trigger` increases. None when Reduce Motion is on.
struct EmberBurst: View {
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var start: Date? = nil

    init(trigger: Int) {
        self.trigger = trigger
    }

    var body: some View {
        ZStack {
            if let began = start {
                TimelineView(.animation) { timeline in
                    EmberCanvas(t: timeline.date.timeIntervalSince(began))
                }
            }
        }
        .frame(width: 160, height: 160)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, newValue in
            guard newValue > 0, !reduceMotion else { return }
            let began: Date = Date()
            start = began
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                if start == began {
                    start = nil
                }
            }
        }
    }
}

/// One frame of the embers (pure function of t).
struct EmberCanvas: View {
    let t: Double

    var body: some View {
        Canvas { context, size in
            EmberCanvas.draw(&context, size: size, t: t)
        }
    }

    static func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let k: Double = t / 0.8
        guard k >= 0, k < 1 else { return }
        let c: CGPoint = CGPoint(x: size.width / 2, y: size.height / 2)
        let eased: Double = 1 - pow(1 - k, 3)
        let alpha: Double = pow(1 - k, 1.4)
        for i in 0..<12 {
            let angle: Double = Double(i) / 12 * 2 * Double.pi + 0.2
            let distance: Double = 26 + Double(i % 3) * 10 + 34 * eased
            let p: CGPoint = CGPoint(x: c.x + CGFloat(cos(angle) * distance), y: c.y + CGFloat(sin(angle) * distance))
            let color: Color = i % 2 == 0 ? Ink.flameTop : Ink.flameMid
            let halo: Path = Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
            let dot: Path = Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
            context.fill(halo, with: .color(color.opacity(0.25 * alpha)))
            context.fill(dot, with: .color(color.opacity(alpha)))
        }
    }
}
