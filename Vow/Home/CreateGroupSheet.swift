import SwiftUI

struct CreateGroupSheet: View {
    /// Called with the new group's id just before the sheet dismisses itself.
    let onCreated: (GroupID) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var vow: String = ""
    @State private var stake: Int = 2
    @State private var isTest: Bool = false
    @State private var busy: Bool = false
    @State private var errorText: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedVow: String {
        vow.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty && !trimmedVow.isEmpty
    }

    var body: some View {
        SheetChrome(title: "New group") {
            FieldSection("Group name") {
                GlassField(placeholder: "Morning crew", text: $name, capitalization: .words)
            }
            FieldSection("Your vow") {
                GlassField(placeholder: "I will train for 30 minutes", text: $vow)
            }
            FieldSection("Daily stake") {
                stakeChips
            }
            if store.testingMode {
                testToggle
            }
            footer
        }
    }

    private var stakeChips: some View {
        HStack(spacing: 10) {
            ForEach(Points.stakeOptions, id: \.self) { option in
                StakeChip(label: GroupFormat.stake(option), selected: option == stake) {
                    stake = option
                }
            }
        }
    }

    private var testToggle: some View {
        Toggle(isOn: $isTest) {
            Text("Test group (advance days manually)")
                .font(Theme.display(15, .medium))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .tint(Theme.cyan)
        .glassCard(padding: 16, radius: 18)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let text = errorText {
                Text(text)
                    .font(Theme.mono(12, .medium))
                    .foregroundStyle(Theme.pink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(title: "Create group", busy: busy, enabled: canCreate, action: create)
            Text("Everyone who joins stakes " + GroupFormat.stake(stake) + " a day. Points only.")
                .font(Theme.mono(11, .medium))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(maxWidth: .infinity)
        }
    }

    private func create() {
        guard canCreate, !busy else { return }
        let groupName: String = trimmedName
        let groupVow: String = trimmedVow
        let groupStake: Int = stake
        let test: Bool = store.testingMode && isTest
        busy = true
        errorText = nil
        Task { @MainActor in
            let newID: GroupID? = await store.createGroup(name: groupName, vow: groupVow, stake: groupStake, isTest: test)
            busy = false
            if let newID = newID {
                onCreated(newID)
                dismiss()
            } else {
                errorText = "Couldn't create the group. " + (store.lastError ?? "Check your iCloud connection and try again.")
            }
        }
    }
}
