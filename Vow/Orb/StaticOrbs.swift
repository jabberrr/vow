import SwiftUI

/// Unlit orb for "not a member yet" and empty Home: dark sphere, faint outer ring, ghosted glyph. Static.
struct DormantOrb: View {
    let theme: DailyTheme
    let size: CGFloat

    init(theme: DailyTheme, size: CGFloat = 150) {
        self.theme = theme
        self.size = size
    }

    private var outer: CGFloat {
        size * 1.13
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                .frame(width: outer, height: outer)
            DormantSphere(size: size)
            GlyphView(model: theme.glyph, lineWidth: 1.6)
                .frame(width: size * 0.56, height: size * 0.56)
                .opacity(0.28)
        }
        .frame(width: outer, height: outer)
        .accessibilityHidden(true)
    }
}

enum MiniOrbState: Equatable {
    case open, sealed, notJoined
}

/// Home row status orb in a (size + 8) square. Decorative (the row label carries the status).
///  .open:      dark sphere + accent ring (your turn)
///  .notJoined: dark sphere + dashed Palette.text3 ring
///  .sealed:    sphere lit in the day's colours with a soft glow and a green check badge
struct MiniOrb: View {
    let theme: DailyTheme
    let state: MiniOrbState
    let size: CGFloat

    init(theme: DailyTheme, state: MiniOrbState, size: CGFloat = 28) {
        self.theme = theme
        self.state = state
        self.size = size
    }

    private var frameSize: CGFloat {
        size + 8
    }

    var body: some View {
        ZStack {
            switch state {
            case .open:
                openOrb
            case .notJoined:
                notJoinedOrb
            case .sealed:
                sealedOrb
            }
        }
        .frame(width: frameSize, height: frameSize)
        .animation(Motion.fade, value: state)
        .accessibilityHidden(true)
    }

    private var openOrb: some View {
        ZStack {
            DormantSphere(size: size)
            Circle()
                .strokeBorder(Palette.accent, lineWidth: 2)
                .frame(width: frameSize, height: frameSize)
        }
    }

    private var notJoinedOrb: some View {
        ZStack {
            DormantSphere(size: size)
            Circle()
                .strokeBorder(Palette.text3, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: frameSize, height: frameSize)
        }
    }

    private var sealedOrb: some View {
        ZStack {
            Circle()
                .fill(glow)
                .frame(width: size * 1.8, height: size * 1.8)
                .allowsHitTesting(false)
            Circle()
                .fill(litFill)
                .frame(width: size, height: size)
            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                .frame(width: size, height: size)
            MiniOrbBadge()
                .frame(width: frameSize, height: frameSize, alignment: .bottomTrailing)
        }
    }

    private var glow: RadialGradient {
        RadialGradient(
            gradient: Gradient(colors: [theme.c1.opacity(0.35), theme.c1.opacity(0)]),
            center: .center,
            startRadius: size * 0.3,
            endRadius: size * 0.9
        )
    }

    /// Same light model as OrbBody: white highlight up-left -> c1 -> c2.
    private var litFill: RadialGradient {
        RadialGradient(
            gradient: Gradient(stops: [
                Gradient.Stop(color: Color.white.opacity(0.9), location: 0.0),
                Gradient.Stop(color: theme.c1, location: 0.2),
                Gradient.Stop(color: theme.c2, location: 0.95)
            ]),
            center: UnitPoint(x: 0.3, y: 0.24),
            startRadius: 0,
            endRadius: size
        )
    }
}

/// Unlit sphere shared by DormantOrb and MiniOrb: Palette.dormant with a faint up-left sheen and a rim.
private struct DormantSphere: View {
    let size: CGFloat

    private var sheen: RadialGradient {
        RadialGradient(
            gradient: Gradient(stops: [
                Gradient.Stop(color: Color.white.opacity(0.10), location: 0.0),
                Gradient.Stop(color: Color.white.opacity(0.03), location: 0.45),
                Gradient.Stop(color: Color.white.opacity(0), location: 1.0)
            ]),
            center: UnitPoint(x: 0.3, y: 0.24),
            startRadius: 0,
            endRadius: size
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.dormant)
            Circle()
                .fill(sheen)
            Circle()
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        }
        .frame(width: size, height: size)
    }
}

/// 15pt green check badge with a 2pt Palette.surface ring (sits on a card row).
private struct MiniOrbBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.surface)
                .frame(width: 19, height: 19)
            Circle()
                .fill(Palette.kept)
                .frame(width: 15, height: 15)
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Palette.onLight)
        }
    }
}
