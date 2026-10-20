import SwiftUI
import UIKit

/// Calls onCreated(newID) on success, then dismisses itself.
/// Name, your vow, daily stake, an optional last day and, in testing mode, the test-group switch.
struct NewGroupSheet: View {
    let onCreated: (GroupID) -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize: DynamicTypeSize

    @State private var name: String = ""
    @State private var vow: String = ""
    @State private var stake: Int = 2
    /// Off by default: a vow has no end unless you choose one.
    @State private var hasEnd: Bool = false
    /// The vow's final day, inclusive. A 30-day vow until you pick another day.
    @State private var lastDay: Date = NewGroupSheet.defaultLastDay(now: Date())
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

    /// Tomorrow (the earliest end, a 2-day vow) to a year out (longer vows are better left open).
    private var lastDayRange: ClosedRange<Date> {
        NewGroupSheet.lastDayRange(now: Date())
    }

    /// Days in the vow, today and the last day included: "30 days".
    private var dayCount: Int {
        DayClock.dayIndex(of: lastDay, start: Date(), timeZoneID: TimeZone.current.identifier) + 1
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
            endField
                .padding(.top, Gap.xl)
            if store.testingMode {
                testField
                    .padding(.top, Gap.xl)
            }
            if let message = errorText {
                FormError(message)
            }
        }
        .animation(Anim.standard, value: hasEnd)
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

    private var endField: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormGroup {
                SwitchRow("End date", isOn: $hasEnd)
                if hasEnd {
                    VStack(spacing: 0) {
                        Hairline()
                        lastDayRow
                    }
                    .transition(.opacity)
                }
            }
            if hasEnd {
                FieldFooter(DayText.count(dayCount))
                    .transition(.opacity)
            }
        }
    }

    /// At accessibility sizes the date goes under the title instead of squeezing it.
    @ViewBuilder
    private var lastDayRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Gap.s) {
                lastDayTitle
                lastDayPicker
            }
            .padding(.horizontal, Gap.l)
            .padding(.vertical, Gap.m)
            .frame(maxWidth: .infinity, minHeight: Gap.control, alignment: .leading)
        } else {
            HStack(spacing: Gap.s) {
                lastDayTitle
                Spacer(minLength: Gap.s)
                lastDayPicker
            }
            .padding(.horizontal, Gap.l)
            .frame(minHeight: Gap.control)
        }
    }

    /// For the eye only: the picker carries the "Last day" label for VoiceOver.
    private var lastDayTitle: some View {
        Text("Last day")
            .font(Fonts.body)
            .foregroundStyle(Ink.text)
            .accessibilityHidden(true)
    }

    private var lastDayPicker: some View {
        DatePicker("Last day", selection: $lastDay, in: lastDayRange, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(Ink.text)
    }

    private var testField: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormGroup {
                SwitchRow("Test group", isOn: $isTest)
            }
            FieldFooter("Days move only when you tap Next day.")
        }
    }

    /// Return closes the keyboard; the stake, end date and test choices below still need a look before Create.
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
        let end: Date? = hasEnd ? lastDay : nil
        busy = true
        errorText = nil
        Task { @MainActor in
            let newID: GroupID? = await store.createGroup(name: groupName, vow: groupVow, stake: groupStake, isTest: test,
                                                          endDate: end)
            busy = false
            if let newID = newID {
                onCreated(newID)
                dismiss()
            } else {
                errorText = "Couldn't create the group. " + (store.lastError ?? "Try again.")
            }
        }
    }

    // MARK: - Last day

    /// Today + 29: a 30-day vow, the length people know from 30-day challenges.
    private static func defaultLastDay(now: Date) -> Date {
        let calendar: Calendar = Calendar.current
        let today: Date = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 29, to: today) ?? today
    }

    private static func lastDayRange(now: Date) -> ClosedRange<Date> {
        let calendar: Calendar = Calendar.current
        let today: Date = calendar.startOfDay(for: now)
        let tomorrow: Date = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let yearOut: Date = calendar.date(byAdding: .day, value: 365, to: today) ?? tomorrow
        return tomorrow...yearOut
    }
}
