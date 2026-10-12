import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var name: String = ""

    /// Blue to pink, close to the app icon.
    static let heroTheme: DailyTheme = DailyTheme.make(cycle: 1, day: 22)

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                column
                    .frame(minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .screenBackground()
    }

    private var column: some View {
        VStack(spacing: 0) {
            hero
            Spacer(minLength: Space.section)
            nameField
            PrimaryButton("Continue", enabled: canContinue, action: submit)
                .padding(.top, 20)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.l)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            SealedOrb(theme: OnboardingView.heroTheme)
                .frame(width: 220, height: 220)
                .accessibilityHidden(true)
            Text("Keep one promise a day.")
                .font(Typeface.title)
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 28)
                .accessibilityAddTraits(.isHeader)
            Text("Make a vow with friends and stake points on it. Miss a day and your stake goes to the ones who kept theirs.")
                .font(Typeface.body)
                .foregroundStyle(Palette.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var nameField: some View {
        FormField("Your name", footer: "Shown to your groups.") {
            VowField("Your name", text: $name, capitalization: .words, submitLabel: .continue)
                .onSubmit(submit)
        }
    }

    private func submit() {
        guard canContinue else { return }
        store.saveProfile(displayName: trimmedName)
        // After "Reset local data" the cache is empty: reload groups from iCloud right away.
        if store.groupIDs.isEmpty {
            Task { await store.refreshAll() }
        }
    }
}
