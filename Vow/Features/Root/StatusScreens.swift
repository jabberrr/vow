import SwiftUI

/// First launch without a cache, while iCloud is checked: the wordmark and a spinner.
struct LaunchScreen: View {
    init() {}

    var body: some View {
        VStack(spacing: Gap.xxl) {
            Text("Vow")
                .font(Fonts.wordmark)
                .foregroundStyle(Ink.text)
                .accessibilityAddTraits(.isHeader)
            ProgressView()
                .tint(Ink.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .vowBackground()
    }
}

/// No iCloud account, or iCloud failed with nothing cached: what is wrong and one way out.
/// Scrolls only if the text outgrows the screen.
struct ProblemScreen: View {
    let systemImage: String
    let title: String
    let message: String
    let onRetry: () -> Void

    init(systemImage: String, title: String, message: String, onRetry: @escaping () -> Void) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.onRetry = onRetry
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                column
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .vowBackground()
    }

    private var column: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Gap.huge)
            problem
            Spacer(minLength: Gap.huge)
            PillButton("Try again", action: onRetry)
                .padding(.bottom, Gap.l)
        }
        .padding(.horizontal, Gap.gutter)
    }

    private var problem: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Ink.text2)
                .accessibilityHidden(true)
            Text(title)
                .font(Fonts.title2)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Gap.xl)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Fonts.subheadline)
                .foregroundStyle(Ink.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Gap.s)
                .padding(.horizontal, Gap.m)
        }
        .frame(maxWidth: .infinity)
    }
}
