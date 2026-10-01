import SwiftUI

/// Ask for (or edit) your vow in a group. Shown after joining and from the group menu.
struct VowPromptSheet: View {
    let id: GroupID

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var vow: String = ""
    @State private var busy: Bool = false
    @State private var didPrefill: Bool = false

    private var group: GroupInfo? {
        store.snapshots[id]?.group
    }

    private var trimmedVow: String {
        vow.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isMember: Bool {
        guard let member = store.myMember(id) else { return false }
        return member.leftDay == nil
    }

    private var explanation: String {
        let stake: String = GroupFormat.stake(group?.stake ?? 0)
        return "Hold the orb each day you keep it. Miss a day and your " + stake + " stake goes to the ones who kept theirs."
    }

    var body: some View {
        SheetChrome(title: "Your vow for " + (group?.name ?? "this group")) {
            Text(explanation)
                .font(Theme.display(15, .regular))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            FieldSection("Your daily vow") {
                GlassField(placeholder: "I will train for 30 minutes", text: $vow)
                    .onSubmit(swear)
            }
            PrimaryButton(title: isMember ? "Save vow" : "Swear it", busy: busy, enabled: !trimmedVow.isEmpty, action: swear)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if !didPrefill {
                didPrefill = true
                vow = store.myMember(id)?.vow ?? ""
            }
        }
    }

    private func swear() {
        let text: String = trimmedVow
        guard !text.isEmpty, !busy else { return }
        busy = true
        Task { @MainActor in
            await store.setVow(text, in: id)
            busy = false
            dismiss()
        }
    }
}
