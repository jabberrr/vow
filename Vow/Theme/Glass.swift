import SwiftUI

private struct GlassCardModifier: ViewModifier {
    let padding: CGFloat
    let radius: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(cardBackground)
            .overlay(shape.strokeBorder(Theme.rim, lineWidth: 0.75))
    }

    private var cardBackground: some View {
        ZStack {
            shape
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 10)
            shape
                .fill(Color.white.opacity(0.05))
        }
    }
}

extension View {
    /// .ultraThinMaterial + white film + Theme.rim hairline + soft static shadow.
    func glassCard(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        modifier(GlassCardModifier(padding: padding, radius: radius))
    }

    /// Mono 11 semibold, tracking 1.6, uppercase, white .55
    func eyebrow() -> some View {
        self
            .font(Theme.mono(11, .semibold))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(Color.white.opacity(0.55))
    }

    func gradientText(_ g: LinearGradient = Theme.brand) -> some View {
        self.foregroundStyle(g)
    }
}
