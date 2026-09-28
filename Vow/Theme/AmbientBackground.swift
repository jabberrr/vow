import SwiftUI

/// Near-black base with soft cyan / pink / purple radial glows. No blur.
struct AmbientBackground: View {
    var body: some View {
        GeometryReader { proxy in
            glows(in: proxy.size)
        }
        .background(Theme.bg)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func glows(in size: CGSize) -> some View {
        let w: CGFloat = max(size.width, 1)
        let h: CGFloat = max(size.height, 1)
        return ZStack {
            Theme.bg
            glow(Theme.cyan, opacity: 0.22, diameter: w * 1.5)
                .position(x: w * 0.05, y: h * 0.06)
            glow(Theme.purple, opacity: 0.20, diameter: w * 1.6)
                .position(x: w * 0.95, y: h * 0.42)
            glow(Theme.pink, opacity: 0.16, diameter: w * 1.4)
                .position(x: w * 0.15, y: h * 0.92)
            glow(Theme.cyan, opacity: 0.08, diameter: w * 1.1)
                .position(x: w * 0.85, y: h * 1.02)
        }
        .frame(width: w, height: h)
    }

    private func glow(_ color: Color, opacity: Double, diameter: CGFloat) -> some View {
        let colors: [Color] = [
            color.opacity(opacity),
            color.opacity(opacity * 0.35),
            color.opacity(0)
        ]
        return Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: colors),
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
    }
}
