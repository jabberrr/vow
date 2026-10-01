import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var name: String = ""
    @State private var didLoad: Bool = false
    @State private var confirmReset: Bool = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveName: Bool {
        !trimmedName.isEmpty && trimmedName != (store.profile?.displayName ?? "")
    }

    private var testingBinding: Binding<Bool> {
        Binding<Bool>(
            get: { store.testingMode },
            set: { newValue in store.testingMode = newValue }
        )
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView(.vertical, showsIndicators: false) {
                column
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            if !didLoad {
                didLoad = true
                name = store.profile?.displayName ?? ""
            }
        }
        .confirmationDialog("Reset local data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset local data", role: .destructive) {
                store.resetLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears your name, cached groups and settings on this iPhone. Groups in iCloud are not deleted.")
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 26) {
            nameSection
            testingSection
            aboutSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 40)
    }

    private var nameSection: some View {
        FieldSection("Display name") {
            GlassField(placeholder: "Your name", text: $name, capitalization: .words)
                .onSubmit(saveName)
            PrimaryButton(title: "Save name", enabled: canSaveName, action: saveName)
        }
    }

    private var testingSection: some View {
        FieldSection("Testing") {
            Toggle(isOn: testingBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Testing mode")
                        .font(Theme.display(16, .semibold))
                        .foregroundStyle(Color.white)
                    Text("Create test groups whose days you advance by hand, and show the test bar.")
                        .font(Theme.mono(11, .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.cyan)
            .glassCard(padding: 16, radius: 18)
            if store.testingMode {
                resetButton
            }
        }
    }

    private var resetButton: some View {
        Button {
            confirmReset = true
        } label: {
            Text("Reset local data")
                .font(Theme.display(16, .semibold))
                .foregroundStyle(Theme.pink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(Theme.pink.opacity(0.10)))
                .overlay(Capsule().strokeBorder(Theme.pink.opacity(0.45), lineWidth: 0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var aboutSection: some View {
        FieldSection("About") {
            Text("Groups sync through iCloud, so every member sees the same days, check-ins and points. Points only — no real money moves.")
                .font(Theme.mono(12, .medium))
                .foregroundStyle(Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveName() {
        guard canSaveName else { return }
        store.saveProfile(displayName: trimmedName)
        store.toast = "Name saved"
    }
}
