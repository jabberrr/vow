import SwiftUI

/// Ask for (or edit) your vow in a group. Shown after joining and from the group menu.
struct VowPromptSheet: View {
    let id: GroupID

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var vow: String = ""
    @State private var busy: Bool = false
    @State private var didPrefill: Bool = false
    /// Wording locked when saving starts: the store adds the member optimistically, which would
    /// otherwise flip "Join" to "Edit vow" while the save is in flight.
    @State private var savingAsMember: Bool? = nil

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

    /// Edit wording for active members, join wording otherwise.
    private var editing: Bool {
        savingAsMember ?? isMember
    }

    private var title: String {
        if editing { return "Edit vow" }
        if let name = group?.name { return "Join \(name)" }
        return "Join group"
    }

    /// The stake rule for newcomers; none when editing.
    private var subtitle: String? {
        guard !editing, let stake = group?.stake else { return nil }
        if stake == 1 {
            return "Miss a day and your 1 pt goes to the ones who kept theirs."
        }
        return "Miss a day and your \(GroupFormat.stake(stake)) go to the ones who kept theirs."
    }

    var body: some View {
        SheetChrome(title: title, subtitle: subtitle) {
            FormField("Your vow") {
                VowField("Your vow", text: $vow, placeholder: "I will run 5k before work", autoFocus: true)
                    .onSubmit(swear)
            }
            PrimaryButton(editing ? "Save" : "Join", busy: busy, enabled: !trimmedVow.isEmpty, action: swear)
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: prefill)
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        vow = store.myMember(id)?.vow ?? ""
    }

    private func swear() {
        let text: String = trimmedVow
        guard !text.isEmpty, !busy else { return }
        savingAsMember = isMember
        busy = true
        Task { @MainActor in
            await store.setVow(text, in: id)
            busy = false
            dismiss()
        }
    }
}
