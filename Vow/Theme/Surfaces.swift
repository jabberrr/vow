import SwiftUI

extension View {
    /// Palette.surface fill, `radius` continuous corners, clipped, 1pt Palette.hairline stroke on top.
    func card(radius: CGFloat = Radius.card) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(Palette.surface))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 1))
    }

    /// Palette.bg behind the view, ignoring safe areas.
    func screenBackground() -> some View {
        self.background(Palette.bg, ignoresSafeAreaEdges: .all)
    }

    /// The check-in room dim. No animation of its own: the caller animates with `withAnimation`
    /// (GroupView picks Motion.dimIn / dimOut / lightsUp).
    func focusDimmed(_ on: Bool) -> some View {
        self.opacity(on ? 0.25 : 1)
    }
}

/// 0.5pt Palette.divider line, indented from the leading edge.
struct InsetDivider: View {
    let leading: CGFloat

    init(leading: CGFloat = 0) {
        self.leading = leading
    }

    var body: some View {
        Rectangle()
            .fill(Palette.divider)
            .frame(height: 0.5)
            .padding(.leading, leading)
            .accessibilityHidden(true)
    }
}

/// Buttons: scale 0.97 and opacity 0.9 while pressed, animated with Motion.press.
/// Labels inherit the environment tint unless they set their own foregroundStyle.
struct PressableStyle: ButtonStyle {
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        let pressed: Bool = configuration.isPressed
        return configuration.label
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(pressed ? 0.9 : 1)
            .animation(Motion.press, value: pressed)
    }
}

/// Full-width rows: Palette.overlay @ 0.55 behind the row while pressed (Motion.press).
/// The whole row rectangle is tappable.
struct RowStyle: ButtonStyle {
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        let pressed: Bool = configuration.isPressed
        return configuration.label
            .contentShape(Rectangle())
            .background(
                Rectangle()
                    .fill(Palette.overlay)
                    .opacity(pressed ? 0.55 : 0)
            )
            .animation(Motion.press, value: pressed)
    }
}
