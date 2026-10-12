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

    /// "1.0 (1)" from the bundle; "1.0" if missing.
    private var versionText: String {
        let info: [String: Any]? = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "1.0" }
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            column
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .onAppear {
            if !didLoad {
                didLoad = true
                name = store.profile?.displayName ?? ""
            }
        }
        .confirmationDialog("Reset local data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                store.resetLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears your name, cached groups and settings on this iPhone. Your groups in iCloud stay.")
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameField
            PrimaryButton("Save", enabled: canSaveName, action: saveName)
                .padding(.top, 14)
            testingField
                .padding(.top, Space.section)
            if store.testingMode {
                resetButton
                    .padding(.top, Space.l)
                    .transition(.opacity)
            }
            aboutField
                .padding(.top, Space.section)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.l)
        .padding(.bottom, Space.huge)
        .animation(Motion.fade, value: store.testingMode)
    }

    private var nameField: some View {
        FormField("Your name", footer: "Shown to your groups.") {
            VowField("Your name", text: $name, capitalization: .words)
                .onSubmit(saveName)
        }
    }

    private var testingField: some View {
        FormField("Testing", footer: "Make test groups whose days move when you tap Next day.") {
            ToggleRow("Testing mode", isOn: testingBinding)
        }
    }

    /// Its own block after the Testing footer; only in testing mode.
    private var resetButton: some View {
        Button {
            confirmReset = true
        } label: {
            Text("Reset local data")
                .font(Typeface.body)
                .foregroundStyle(Palette.loss)
                .frame(maxWidth: .infinity, minHeight: Space.fieldHeight)
                .background(fieldShape.fill(Palette.raised))
                .contentShape(fieldShape)
        }
        .buttonStyle(PressableStyle())
    }

    private var aboutField: some View {
        FormField("About", footer: "Groups sync through iCloud. Points only, no real money.") {
            versionRow
        }
    }

    private var versionRow: some View {
        HStack {
            Text("Version")
                .foregroundStyle(Palette.text)
            Spacer(minLength: Space.s)
            Text(versionText)
                .foregroundStyle(Palette.text2)
                .monospacedDigit()
        }
        .font(Typeface.body)
        .padding(.horizontal, 16)
        .frame(minHeight: Space.fieldHeight)
        .background(fieldShape.fill(Palette.raised))
        .accessibilityElement(children: .combine)
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
    }

    private func saveName() {
        guard canSaveName else { return }
        store.saveProfile(displayName: trimmedName)
        store.toast = "Name saved"
    }
}
