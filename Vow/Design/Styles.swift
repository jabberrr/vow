import SwiftUI

/// Buttons and pills: slight shrink and fade while pressed.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Anim.press, value: configuration.isPressed)
    }
}

/// Rows inside cards: pressed background.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Ink.pressed : Color.clear)
            .contentShape(Rectangle())
            .animation(Anim.press, value: configuration.isPressed)
    }
}

extension View {
    /// Card fill, hairline border, clipped to the radius.
    func cardSurface(radius: CGFloat = Corner.card) -> some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(Ink.card))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Ink.hairline, lineWidth: 1))
    }

    /// Full-bleed screen background.
    func vowBackground() -> some View {
        self.background(Ink.bg.ignoresSafeArea())
    }

    /// Per-view fade while the orb is held. Opacity only: never blocks touches.
    func roomDim(_ on: Bool) -> some View {
        self.opacity(on ? Anim.dimmedOpacity : 1)
    }

    /// Standard sheet presentation.
    func vowSheet(_ detents: Set<PresentationDetent>) -> some View {
        self
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(Ink.sheet)
            .presentationCornerRadius(Corner.sheet)
    }
}

/// Section title with an optional trailing note, baseline aligned.
struct SectionTitle: View {
    let title: String
    let trailing: String?
    let trailingColor: Color

    init(_ title: String, trailing: String? = nil, trailingColor: Color = Ink.text2) {
        self.title = title
        self.trailing = trailing
        self.trailingColor = trailingColor
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
            Text(title)
                .font(Fonts.section)
                .foregroundStyle(Ink.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Gap.s)
            if let note = trailing {
                Text(note)
                    .font(Fonts.subheadlineMedium)
                    .foregroundStyle(trailingColor)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Gap.xs)
        .padding(.bottom, 10)
    }
}

/// 1 pt divider inside cards.
struct Hairline: View {
    let leading: CGFloat

    init(leading: CGFloat = 16) {
        self.leading = leading
    }

    var body: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: 1)
            .padding(.leading, leading)
            .accessibilityHidden(true)
    }
}

/// Digit roll for a changing number; a plain swap when Reduce Motion is on.
struct RollingNumber: ViewModifier {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? ContentTransition.identity : ContentTransition.numericText(value: value))
    }
}

extension View {
    func rollingNumber(_ value: Double) -> some View {
        self.modifier(RollingNumber(value: value))
    }
}
