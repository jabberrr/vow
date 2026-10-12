import SwiftUI

/// The stage while you're not a member yet: an unlit orb, the stake, and "Set vow".
struct JoinPrompt: View {
    let theme: DailyTheme
    let stake: Int
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DormantOrb(theme: theme)
            Text("You're not in yet")
                .font(Typeface.title3)
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 26)
            Text("Set your vow to join. \(GroupFormat.stake(stake)) a day.")
                .font(Typeface.subheadline)
                .foregroundStyle(Palette.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            PrimaryButton("Set vow", action: action)
                .frame(width: 220)
                .padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
    }
}
