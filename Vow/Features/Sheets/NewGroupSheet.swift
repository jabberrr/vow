import SwiftUI
import UIKit

/// Calls onCreated(newID) on success, then dismisses itself.
/// Name, your vow, daily stake and, in testing mode, the test-group switch.
struct NewGroupSheet: View {
    let onCreated: (GroupID) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var vow: String = ""
    @State private var stake: Int = 2
    @State private var isTest: Bool = false
    @State private var busy: Bool = false
    @State private var errorText: String? = nil

    init(onCreated: @escaping (GroupID) -> Void) {
        self.onCreated = onCreated
    }

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
        SheetScaffold(title: "New group", onClose: close) {
            form
        } footer: {
            PillButton("Create group", busy: busy, enabled: canCreate, action: create)
        }
        .interactiveDismissDisabled(busy)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameField
            vowField
                .padding(.top, Gap.xl)
            stakeField
                .padding(.top, Gap.xl)
            if store.testingMode {
                testField
                    .padding(.top, Gap.xl)
            }
            if let message = errorText {
                FormError(message)
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Name")
            VowTextField("Name", text: $name, placeholder: "Morning run", capitalization: .words, autoFocus: true)
        }
    }

    private var vowField: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Your vow")
            VowTextField("Your vow", text: $vow, placeholder: "I will run 5k before work", multiline: true, onReturn: endEditing)
        }
    }

    private var stakeField: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Daily stake")
            StakeSelector(selection: $stake)
            FieldFooter(StakeText.rule(stake))
        }
    }

    private var testField: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormGroup {
                SwitchRow("Test group", isOn: $isTest)
            }
            FieldFooter("Days move only when you tap Next day.")
        }
    }

    /// Return closes the keyboard; the stake and test choices below still need a look before Create.
    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Not while saving: MainView must still be showing this sheet when onCreated arrives.
    private func close() {
        guard !busy else { return }
        dismiss()
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
