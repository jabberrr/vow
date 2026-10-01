import SwiftUI

/// Quiet first-launch loading state: logo + spinner.
struct LoadingScreen: View {
    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 18) {
                Text("Vow")
                    .font(Theme.display(44, .heavy))
                    .gradientText()
                ProgressView()
                    .tint(Color.white.opacity(0.7))
            }
        }
    }
}

/// Full-screen card for account / connection problems, with a retry action.
struct PhaseScreen: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        ZStack {
            AmbientBackground()
            card
                .padding(.horizontal, 20)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.cyan)
            Text(title)
                .font(Theme.display(26, .heavy))
                .gradientText()
            Text(message)
                .font(Theme.display(15, .regular))
                .foregroundStyle(Color.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: actionTitle, action: action)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 22, radius: 26)
    }
}
