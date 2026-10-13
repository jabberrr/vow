import SwiftUI

/// First launch: what Vow is, and the name your groups see.
struct OnboardingScreen: View {
    @Environment(AppStore.self) private var store
    @State private var name: String = ""

    /// Blue to pink, close to the app icon.
    private static let heroTheme: DailyTheme = DailyTheme.make(cycle: 1, day: 22)
    /// The orb's top below the safe area (140 pt on a 393 × 852 screen).
    private static let heroTop: CGFloat = 80

    init() {}

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                column(compact: proxy.size.height < 700)
                    .frame(minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .vowBackground()
    }

    private func column(compact: Bool) -> some View {
        VStack(spacing: 0) {
            hero
                .padding(.top, compact ? Gap.xxl : OnboardingScreen.heroTop)
            Spacer(minLength: Gap.section)
            nameField
            PillButton("Continue", enabled: canContinue, action: submit)
                .padding(.top, Gap.xl)
        }
        .padding(.horizontal, Gap.gutter)
        .padding(.bottom, compact ? Gap.l : Gap.xxxl)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            SealedOrb(theme: OnboardingScreen.heroTheme)
                .accessibilityHidden(true)
            Text("Keep one promise a day")
                .font(Fonts.title)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 36)
                .accessibilityAddTraits(.isHeader)
            Text("Make a vow with friends. Miss a day and your points go to the ones who kept theirs.")
                .font(Fonts.callout)
                .foregroundStyle(Ink.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.horizontal, Gap.m)
        }
        .frame(maxWidth: .infinity)
    }

    private var nameField: some View {
        VStack(spacing: 0) {
            FieldLabel("Your name")
            VowTextField("Your name",
                         text: $name,
                         placeholder: "Name",
                         capitalization: .words,
                         submitLabel: .continue)
                .onSubmit(submit)
            FieldFooter("Your groups see this.")
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
