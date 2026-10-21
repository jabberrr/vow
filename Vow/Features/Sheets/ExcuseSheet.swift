import SwiftUI
import UIKit

/// Today's excuse instead of a check-in, which the group sees in Chat and can overrule. Sending closes
/// today's orb for good, so the sheet asks once first. The store adds the excuse at once, so Home swaps
/// the orb for the excused sphere behind the sheet, and back if the save fails; the sheet then stays
/// with the text kept. It closes itself, without a word, once today can't be excused any more: a check-in
/// or an excuse from another device, leaving, or the day ending.
struct ExcuseSheet: View {
    let id: GroupID

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var busy: Bool = false
    @State private var failed: Bool = false
    @State private var confirming: Bool = false
    /// The group day the sheet opened on: an excuse written for it never lands on the next.
    @State private var day: Int? = nil

    init(id: GroupID) {
        self.id = id
    }

    /// "{n} left" shows once this few characters remain.
    private static let counterFrom: Int = 40

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Never below 0, even for the moment a paste runs past the limit before it is clamped.
    private var remaining: Int {
        max(0, Records.excuseTextLimit - text.count)
    }

    /// Your short vow ("Run 5k before work"); nil without one.
    private var subtitle: String? {
        guard let vow: String = store.myMember(id)?.vow, !vow.isEmpty else { return nil }
        return VowFormat.short(vow)
    }

    /// Someone can overrule today's excuse. Alone, nobody can, so the footer doesn't mention it.
    private var hasVoters: Bool {
        guard let uid: String = store.userID, let snapshot: GroupSnapshot = store.snapshots[id] else { return false }
        let today: Int = DayClock.currentDay(snapshot.group, now: Date())
        return !Review.eligibleVoters(subject: uid, day: today, snapshot: snapshot).isEmpty
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            SheetScaffold(title: "Excuse for today", subtitle: subtitle, onClose: { dismiss() }) {
                form
            } footer: {
                sendButton
            }
            .onChange(of: isExcusable(now: context.date)) { _, open in
                if !open {
                    closeIfStale()
                }
            }
        }
        .onChange(of: text) { _, value in
            clamp(value)
        }
        .task {
            settleDay()
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            VowTextField("Your excuse",
                         text: $text,
                         placeholder: "Sick, staying in bed",
                         autoFocus: true,
                         multiline: true,
                         onReturn: endEditing)
            if remaining <= ExcuseSheet.counterFrom {
                counter
            }
            FieldFooter(hasVoters
                        ? "If the group doesn't overrule it, your streak pauses and no points move."
                        : "Your streak pauses and no points move.")
            if failed {
                FormError("Couldn't send your excuse. Try again.")
            }
        }
    }

    /// "12 left", trailing under the field.
    private var counter: some View {
        Text("\(remaining) left")
            .font(Fonts.footnote)
            .monospacedDigit()
            .foregroundStyle(Ink.text3)
            .padding(.horizontal, Gap.xs)
            .padding(.top, Gap.s)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// The warning is the confirmation's alone. It hangs off the button that asks for it, which iOS 26
    /// anchors it to. Sending isn't a loss, so "Send excuse" keeps the default role.
    private var sendButton: some View {
        PillButton("Send excuse", busy: busy, enabled: !trimmed.isEmpty, action: ask)
            .confirmationDialog("Send excuse?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Send excuse", action: send)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The orb closes for today. You can't check in after this.")
            }
    }

    // MARK: - Sending

    private func ask() {
        guard !trimmed.isEmpty, !busy else { return }
        endEditing()
        confirming = true
    }

    /// Sent: the sheet closes and the screen shows it, with no toast. Not sent: the text stays with the
    /// error, unless today can't be excused any more.
    private func send() {
        let excuse: String = trimmed
        guard !excuse.isEmpty, !busy else { return }
        busy = true
        failed = false
        Task { @MainActor in
            let sent: Bool = await store.sendExcuse(excuse, in: id)
            busy = false
            if sent {
                dismiss()
            } else {
                failed = true
                closeIfStale()
            }
        }
    }

    private func clamp(_ value: String) {
        guard value.count > Records.excuseTextLimit else { return }
        text = String(value.prefix(Records.excuseTextLimit))
    }

    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Staleness

    /// Pins the day the sheet opened on, and closes at once if that day can't be excused already.
    private func settleDay() {
        if let group: GroupInfo = store.snapshots[id]?.group {
            day = DayClock.currentDay(group, now: Date())
        }
        closeIfStale()
    }

    /// Today can still be excused, as the store would allow it (`canExcuse`), and it is still the day the
    /// sheet opened on.
    private func isExcusable(now: Date) -> Bool {
        guard store.canExcuse(id, now: now) else { return false }
        guard let opened: Int = day, let group: GroupInfo = store.snapshots[id]?.group else { return true }
        return opened == DayClock.currentDay(group, now: now)
    }

    /// Never while sending: the store's own optimistic excuse closes today until the save settles.
    private func closeIfStale() {
        guard !busy, !isExcusable(now: Date()) else { return }
        dismiss()
    }
}
