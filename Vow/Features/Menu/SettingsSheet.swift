import SwiftUI
import UIKit
import UserNotifications

/// Name, reminder, testing, about. Presented by the bar's gear and by the Menu's Settings button.
struct SettingsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(ReminderCenter.self) private var reminders
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var name: String = ""
    @State private var didLoad: Bool = false
    @State private var confirmReset: Bool = false
    /// While the permission prompt is up the switch stays on.
    @State private var enabling: Bool = false
    /// A name was saved during this visit. The toast waits for the sheet to close (it would sit behind it).
    @State private var savedName: Bool = false
    /// Set by Reset local data: nothing is saved on the way out.
    @State private var didReset: Bool = false

    init() {}

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveName: Bool {
        !trimmedName.isEmpty && trimmedName != (store.profile?.displayName ?? "")
    }

    private var denied: Bool {
        reminders.authorization == .denied
    }

    private var reminderOn: Bool {
        (reminders.isOn || enabling) && !denied
    }

    private var reminderBinding: Binding<Bool> {
        Binding<Bool>(
            get: { reminderOn },
            set: { newValue in setReminder(newValue) }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding<Date>(
            get: { SettingsSheet.date(minuteOfDay: reminders.minuteOfDay) },
            set: { newValue in setTime(newValue) }
        )
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
        SheetScaffold(title: "Settings", onClose: { dismiss() }) {
            column
        } footer: {
            EmptyView()
        }
        .onAppear(perform: load)
        .onDisappear(perform: finish)
        .task {
            await reminders.refreshAuthorization()
        }
        .confirmationDialog("Reset local data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                resetLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears your name, cached groups and settings on this iPhone. Your groups in iCloud stay.")
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameSection
            reminderSection
                .padding(.top, Gap.xxl)
            testingSection
                .padding(.top, Gap.xxl)
            aboutSection
                .padding(.top, Gap.xxl)
        }
        .animation(Anim.fade, value: store.testingMode)
        .animation(Anim.fade, value: reminderOn)
        .animation(Anim.fade, value: denied)
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Name")
            VowTextField("Name", text: $name, capitalization: .words)
                .onSubmit(saveName)
            FieldFooter("Your groups see this.")
        }
    }

    // MARK: - Reminder

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Reminder")
            FormGroup {
                SwitchRow("Daily reminder", isOn: reminderBinding)
                    .disabled(denied)
                if reminderOn {
                    VStack(spacing: 0) {
                        Hairline()
                        timeRow
                    }
                    .transition(.opacity)
                }
            }
            if denied {
                FieldFooter("Notifications are off for Vow.")
                openSettingsButton
            } else {
                FieldFooter("Only on days a vow is still open.")
            }
        }
    }

    private var timeRow: some View {
        DatePicker(selection: timeBinding, displayedComponents: .hourAndMinute) {
            Text("Time")
                .font(Fonts.body)
                .foregroundStyle(Ink.text)
        }
        .datePickerStyle(.compact)
        .padding(.horizontal, Gap.l)
        .frame(minHeight: Gap.control)
    }

    private var openSettingsButton: some View {
        Button(action: openNotificationSettings) {
            Text("Open Settings")
                .font(Fonts.footnoteSemibold)
                .foregroundStyle(Ink.text)
                .padding(.horizontal, Gap.xs)
                .frame(minHeight: Gap.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    // MARK: - Testing

    private var testingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Testing")
            FormGroup {
                SwitchRow("Testing mode", isOn: testingBinding)
                if store.testingMode {
                    VStack(spacing: 0) {
                        Hairline()
                        resetRow
                    }
                    .transition(.opacity)
                }
            }
            FieldFooter("Make test groups whose days move when you tap Next day.")
        }
    }

    private var resetRow: some View {
        Button {
            confirmReset = true
        } label: {
            Text("Reset local data")
                .font(Fonts.body)
                .foregroundStyle(Ink.loss)
                .padding(.horizontal, Gap.l)
                .frame(maxWidth: .infinity, minHeight: Gap.control, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("About")
            FormGroup {
                ValueRow("Version", value: versionText)
            }
            FieldFooter("Groups sync through iCloud. Points only, no real money.")
        }
    }

    // MARK: - Actions

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        name = store.profile?.displayName ?? ""
    }

    private func saveName() {
        guard !didReset, canSaveName else { return }
        store.saveProfile(displayName: trimmedName)
        savedName = true
    }

    /// On the way out: save a changed name, then confirm any save made during this visit.
    private func finish() {
        guard !didReset else { return }
        saveName()
        if savedName {
            store.toast = "Name saved."
        }
    }

    private func setReminder(_ on: Bool) {
        guard !enabling else { return }
        if on {
            guard !reminders.isOn else { return }
            enabling = true
            Task { @MainActor in
                _ = await reminders.enable()
                syncReminders()
                enabling = false
            }
        } else {
            reminders.disable()
        }
    }

    private func setTime(_ date: Date) {
        let parts: DateComponents = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute: Int = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard minute != reminders.minuteOfDay else { return }
        reminders.setMinuteOfDay(minute)
        syncReminders()
    }

    private func syncReminders() {
        reminders.sync(groups: store.reminderGroups(store.summaries()), now: Date())
    }

    private func openNotificationSettings() {
        guard let url: URL = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        openURL(url)
    }

    /// The root then shows onboarding, which takes this sheet with it.
    private func resetLocalData() {
        didReset = true
        store.resetLocalData()
        reminders.resetAfterLocalDataReset()
    }

    /// Today at that minute (anchored on today, so DST and calendars behave).
    private static func date(minuteOfDay: Int) -> Date {
        let now: Date = Date()
        return Calendar.current.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: now) ?? now
    }
}
