import SwiftUI

/// First-launch loading state: wordmark + spinner.
struct LoadingScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Vow")
                .font(Typeface.wordmarkLarge)
                .foregroundStyle(Palette.text)
            ProgressView()
                .tint(Palette.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

/// Full-screen account / connection problem with one way out. Scrolls only if the text outgrows the screen.
struct PhaseScreen: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                column
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .screenBackground()
    }

    private var column: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.huge)
            problem
            Spacer(minLength: Space.huge)
            PrimaryButton(actionTitle, action: action)
                .padding(.bottom, Space.l)
        }
        .padding(.horizontal, Space.gutter)
    }

    private var problem: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Palette.text2)
                .accessibilityHidden(true)
            Text(title)
                .font(Typeface.title2)
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Typeface.body)
                .foregroundStyle(Palette.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
    }
}
