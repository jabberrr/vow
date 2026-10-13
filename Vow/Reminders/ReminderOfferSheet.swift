import SwiftUI

/// Once, after the first kept day in a real group. Layout §6.21. "Turn on" asks for permission
/// (the system prompt appears only now) and schedules; "Not now" and a swipe both close it for good.
struct ReminderOfferSheet: View {
    @Environment(ReminderCenter.self) private var reminders: ReminderCenter
    @Environment(AppStore.self) private var store: AppStore
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var busy: Bool = false

    init() {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                bell
                title
                    .padding(.top, 14)
                detail
                    .padding(.top, 6)
                buttons
                    .padding(.top, Gap.xxl)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Gap.xxl)
            .padding(.top, 30)
            .padding(.bottom, Gap.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Ink.sheet.ignoresSafeArea())
        .interactiveDismissDisabled(busy)
        .onDisappear {
            reminders.markAsked()
        }
    }

    private var bell: some View {
        Image(systemName: "bell")
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(Ink.text)
            .frame(width: 52, height: 52)
            .background(Circle().fill(Ink.field))
            .accessibilityHidden(true)
    }

    private var title: some View {
        Text("Daily reminder")
            .font(Fonts.title2)
            .foregroundStyle(Ink.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var detail: some View {
        Text("\(reminders.timeText), only on days a vow is still open.")
            .font(Fonts.subheadline)
            .foregroundStyle(Ink.text2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            PillButton("Turn on", busy: busy, action: turnOn)
            PillButton("Not now", kind: .secondary, action: notNow)
        }
    }

    private func turnOn() {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            _ = await reminders.enable()
            reminders.sync(groups: store.reminderGroups(store.summaries()), now: Date())
            dismiss()
        }
    }

    private func notNow() {
        guard !busy else { return }
        reminders.markAsked()
        dismiss()
    }
}
