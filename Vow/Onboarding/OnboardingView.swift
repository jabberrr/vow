import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var name: String = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView(.vertical, showsIndicators: false) {
                content
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            hero
            FieldSection("Your name") {
                GlassField(placeholder: "What should your crew call you?", text: $name, capitalization: .words)
                    .onSubmit(submit)
            }
            PrimaryButton(title: "Continue", enabled: canContinue, action: submit)
            footnote
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 40)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vow")
                .eyebrow()
            Text("Make a vow.\nKeep the streak alive.")
                .font(Theme.display(34, .heavy))
                .gradientText()
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                heroLine("Make a daily vow with friends and stake points on it.")
                heroLine("Miss a day and your stake goes to the ones who kept theirs.")
            }
        }
    }

    private func heroLine(_ text: String) -> some View {
        Text(text)
            .font(Theme.display(15, .regular))
            .foregroundStyle(Color.white.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footnote: some View {
        Text("Groups sync through iCloud · points only")
            .font(Theme.mono(11, .medium))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(maxWidth: .infinity)
    }

    private func submit() {
        guard canContinue else { return }
        store.saveProfile(displayName: trimmedName)
    }
}
