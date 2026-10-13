import SwiftUI

enum SphereState: Equatable {
    /// Kept today: lit in the day's colours.
    case lit
    /// Your turn: unlit with an outer ring.
    case open
    /// Not yet / not a member.
    case unlit
    /// A missed closed day (chain only).
    case missed
}

/// The app's one status shape, drawn with the orb's light model. Decorative (hidden from VoiceOver);
/// the owner supplies the label. Lit and unlit layers are always present and crossfade, so
/// `.animation(Anim.light, value: state)` at the call site animates the light-up.
struct Sphere: View {
    let theme: DailyTheme
    let state: SphereState
    let size: CGFloat
    let initial: String?
    let showsGlyph: Bool
    let ringColor: Color
    let glows: Bool

    init(theme: DailyTheme,
         state: SphereState,
         size: CGFloat,
         initial: String? = nil,
         showsGlyph: Bool = false,
         ringColor: Color = Ink.text,
         glows: Bool = true) {
        self.theme = theme
        self.state = state
        self.size = size
        self.initial = initial
        self.showsGlyph = showsGlyph
        self.ringColor = ringColor
        self.glows = glows
    }

    private var isLit: Bool {
        state == .lit
    }

    var body: some View {
        ZStack {
            unlitBody
                .opacity(isLit ? 0 : 1)
            litBody
                .opacity(isLit ? 1 : 0)
            if showsGlyph {
                GlyphView(model: theme.glyph, lineWidth: glyphLineWidth)
                    .frame(width: size * 0.56, height: size * 0.56)
                    .opacity(isLit ? 1 : 0.28)
            }
            if let letter = initial {
                initialText(letter)
            }
        }
        .frame(width: size, height: size)
        .background(glow)
        .overlay(ring)
        .accessibilityHidden(true)
    }

    private var glyphLineWidth: CGFloat {
        min(1.6, max(0.9, size / 34))
    }

    private var litBody: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(stops: [
                        Gradient.Stop(color: Color.white.opacity(0.9), location: 0.0),
                        Gradient.Stop(color: theme.c1, location: 0.2),
                        Gradient.Stop(color: theme.c2, location: 0.95)
                    ]),
                    center: UnitPoint(x: 0.3, y: 0.24),
                    startRadius: 0,
                    endRadius: size))
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0.28)]),
                    center: UnitPoint(x: 0.4, y: 0.36),
                    startRadius: size * 0.27,
                    endRadius: size * 0.69))
            Circle()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        }
    }

    private var unlitBody: some View {
        ZStack {
            Circle()
                .fill(state == .missed ? Ink.missed : Ink.unlit)
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(stops: [
                        Gradient.Stop(color: Color.white.opacity(0.10), location: 0.0),
                        Gradient.Stop(color: Color.white.opacity(0.03), location: 0.45),
                        Gradient.Stop(color: Color.white.opacity(0), location: 1.0)
                    ]),
                    center: UnitPoint(x: 0.3, y: 0.24),
                    startRadius: 0,
                    endRadius: size))
            Circle()
                .strokeBorder(state == .missed ? Ink.loss.opacity(0.45) : Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    /// Drawn in .background so it never changes layout.
    @ViewBuilder
    private var glow: some View {
        if glows && size >= 24 {
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [theme.c1.opacity(0.42), theme.c1.opacity(0)]),
                    center: .center,
                    startRadius: size * 0.25,
                    endRadius: size * 0.78))
                .frame(width: size * 1.56, height: size * 1.56)
                .opacity(isLit ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    /// Outer ring for .open, drawn in .overlay so it never changes layout.
    @ViewBuilder
    private var ring: some View {
        if state == .open {
            Circle()
                .strokeBorder(ringColor, lineWidth: size < 30 ? 1.5 : 1.75)
                .frame(width: size + (size < 30 ? 5 : 6), height: size + (size < 30 ? 5 : 6))
                .allowsHitTesting(false)
        }
    }

    private func initialText(_ letter: String) -> some View {
        Text(letter)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(isLit ? Color.white : Ink.text2)
            .shadow(color: Color.black.opacity(isLit ? 0.35 : 0), radius: 1, x: 0, y: 1)
    }
}
