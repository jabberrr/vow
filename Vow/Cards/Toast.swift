import SwiftUI

struct Toast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.mono(13, .medium))
            .foregroundStyle(Color.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(cardBackground)
            .overlay(Capsule().strokeBorder(Theme.rim, lineWidth: 0.75))
    }

    private var cardBackground: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 10)
            Capsule()
                .fill(Color.white.opacity(0.05))
        }
    }
}
