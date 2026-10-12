import SwiftUI

/// New group form: name, your vow, daily stake and, in testing mode, the test-group toggle.
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

    /// The stake rule, phrased for the selected stake.
    private var stakeFooter: String {
        if stake == 1 {
            return "Miss a day and your 1 pt goes to the ones who kept theirs."
        }
        return "Miss a day and your \(stake) pts go to the ones who kept theirs."
    }

    var body: some View {
        SheetChrome(title: "New group") {
            nameField
            vowField
            stakeField
            if store.testingMode {
                testField
            }
            if let message = errorText {
                ErrorText(message)
            }
            PrimaryButton("Create group", busy: busy, enabled: canCreate, action: create)
        }
    }

    private var nameField: some View {
        FormField("Name") {
            VowField("Name", text: $name, placeholder: "Morning run", capitalization: .words, autoFocus: true)
        }
    }

    private var vowField: some View {
        FormField("Your vow") {
            VowField("Your vow", text: $vow, placeholder: "I will run 5k before work")
        }
    }

    private var stakeField: some View {
        FormField("Daily stake", footer: stakeFooter) {
            StakePicker(selection: $stake)
        }
    }

    private var testField: some View {
        FormField(footer: "Days move only when you tap Next day.") {
            ToggleRow("Test group", isOn: $isTest)
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
                errorText = "Couldn't create the group. " + (store.lastError ?? "Try again.")
            }
        }
    }
}
