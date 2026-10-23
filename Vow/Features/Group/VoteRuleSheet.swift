import SwiftUI
import UIKit

/// The owner picks how many of the others it takes to overrule a check-in or excuse: more than half,
/// everyone, or a number of their own. It opens on tomorrow's rule, the one a save replaces: a change starts
/// tomorrow, so no day already open to votes is judged again. A legacy Two thirds is no longer offered, so
/// then nothing is chosen until the owner picks. Saves, then closes; the store's toast says what changed.
struct VoteRuleSheet: View {
    let id: GroupID

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// nil until a row is tapped: the sheet shows tomorrow's rule.
    @State private var picked: VoteRuleChoice? = nil
    /// Custom's number as typed; nil until then: tomorrow's count, or `suggestedCount`.
    @State private var typed: String? = nil
    @State private var busy: Bool = false

    init(id: GroupID) {
        self.id = id
    }

    /// Custom's number before the owner types one, when tomorrow's rule isn't already a count.
    private static let suggestedCount: Int = 2

    private var group: GroupInfo? {
        store.snapshots[id]?.group
    }

    /// Tomorrow's rule (a test group's tomorrow is the day after `testDay`).
    private var tomorrow: VoteRule {
        guard let g: GroupInfo = group else { return .majority }
        return Review.rule(forDay: DayClock.currentDay(g, now: Date()) + 1, group: g)
    }

    private var choice: VoteRuleChoice? {
        picked ?? VoteRuleChoice(tomorrow)
    }

    /// Who votes on a claim: every active member but the one who made it.
    private var others: Int {
        guard let snapshot: GroupSnapshot = store.snapshots[id] else { return 0 }
        var active: Int = 0
        for m in Settlement.orderedMembers(snapshot.members) where m.leftDay == nil {
            active += 1
        }
        return max(0, active - 1)
    }

    /// "How many of the 4 others must say a check-in or excuse doesn't count."
    private var subtitle: String {
        switch others {
        case 0:
            return "Applies once others join."
        case 1:
            return "How many others must say a check-in or excuse doesn't count."
        default:
            return "How many of the \(others) others must say a check-in or excuse doesn't count."
        }
    }

    private var countText: String {
        typed ?? String(defaultCount)
    }

    private var defaultCount: Int {
        if case .count(let k) = tomorrow {
            return VoteRuleSheet.clamp(k)
        }
        return VoteRuleSheet.suggestedCount
    }

    /// Custom's number; nil while its box is empty.
    private var customCount: Int? {
        guard let n: Int = Int(countText) else { return nil }
        return VoteRuleSheet.clamp(n)
    }

    /// What Save would set: nil while nothing is chosen (a legacy rule) or Custom's box is empty.
    private var chosenRule: VoteRule? {
        guard let c: VoteRuleChoice = choice else { return nil }
        return rule(for: c)
    }

    private var canSave: Bool {
        guard group != nil, let next: VoteRule = chosenRule else { return false }
        return next != tomorrow
    }

    var body: some View {
        SheetScaffold(title: "Overrule with", subtitle: subtitle, onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 0) {
                options
                if choice == .custom {
                    countBox
                }
                FieldFooter("Changes start tomorrow. Days already being voted on keep their rule.")
            }
        } footer: {
            PillButton("Save", busy: busy, enabled: canSave, action: save)
        }
        .onChange(of: typed) { (_: String?, text: String?) in
            clampTyped(text)
        }
    }

    // MARK: - Choices

    /// Each with what it takes among today's others ("2 of 3 others"), hidden while there are none.
    private var options: some View {
        let voters: Int = others
        let current: VoteRuleChoice? = choice
        return FormGroup {
            ForEach(VoteRuleChoice.allCases, id: \.self) { (c: VoteRuleChoice) in
                if c != VoteRuleChoice.allCases.first {
                    Hairline(leading: 16)
                }
                VoteRuleOption(title: c.title,
                               hint: VoteRuleSheet.hint(rule(for: c), others: voters),
                               selected: c == current,
                               action: { pick(c) })
            }
        }
    }

    /// Custom's number pad has no return key: Save stays above it, and another row or a scroll puts it away.
    /// It rises by itself only when the owner has just picked Custom, not when the sheet opens on it.
    private var countBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("Votes needed")
            VowTextField("Votes needed",
                         text: Binding<String>(get: { () -> String in countText },
                                               set: { (text: String) -> Void in typed = text }),
                         placeholder: String(VoteRuleSheet.suggestedCount),
                         capitalization: .never,
                         autoFocus: picked == .custom)
                .keyboardType(.numberPad)
            FieldFooter("When fewer of the others take part that day, it takes all of them.")
        }
        .padding(.top, Gap.l)
    }

    private func rule(for c: VoteRuleChoice) -> VoteRule? {
        switch c {
        case .majority:
            return .majority
        case .everyone:
            return .everyone
        case .custom:
            guard let k: Int = customCount else { return nil }
            return .count(k)
        }
    }

    /// "2 of 3 others", "1 of 1 other"; nil with nobody else, or no number for Custom.
    private static func hint(_ rule: VoteRule?, others: Int) -> String? {
        guard let r: VoteRule = rule, others > 0 else { return nil }
        let needed: Int = r.needed(voters: others)
        return "\(needed) of \(others) " + (others == 1 ? "other" : "others")
    }

    private func pick(_ c: VoteRuleChoice) {
        guard !busy else { return }
        picked = c
    }

    // MARK: - Custom's number

    /// Digits only, within `VoteRule.customRange`; left empty while the owner retypes it. Written back only
    /// when it differs, so a fourth digit or a paste is undone in the box as well.
    private func clampTyped(_ text: String?) {
        guard let raw: String = text else { return }
        let digits: String = raw.filter { (c: Character) -> Bool in c.isASCII && c.isNumber }
        let clean: String = digits.isEmpty ? "" : String(VoteRuleSheet.clamp(Int(digits) ?? Int.max))
        if clean != raw {
            typed = clean
        }
    }

    private static func clamp(_ n: Int) -> Int {
        return min(max(n, VoteRule.customRange.lowerBound), VoteRule.customRange.upperBound)
    }

    // MARK: - Saving

    private func save() {
        guard !busy, canSave, let next: VoteRule = chosenRule else { return }
        endEditing()
        busy = true
        Task { @MainActor in
            await store.setVoteRule(next, in: id)
            busy = false
            dismiss()
        }
    }

    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// What the sheet offers. Two thirds is no longer among them: a group still on it sees nothing chosen.
private enum VoteRuleChoice: CaseIterable {
    case majority
    case everyone
    case custom

    /// The choice a rule shows as; nil for the legacy Two thirds.
    init?(_ rule: VoteRule) {
        switch rule {
        case .majority:
            self = .majority
        case .everyone:
            self = .everyone
        case .count:
            self = .custom
        case .twoThirds:
            return nil
        }
    }

    var title: String {
        switch self {
        case .majority: return VoteRuleText.title(.majority)
        case .everyone: return VoteRuleText.title(.everyone)
        case .custom: return "Custom"
        }
    }
}

/// One rule: its title, what it takes now, and a checkmark on the chosen one. One VoiceOver button:
/// "More than half, 2 of 3 others", selected.
private struct VoteRuleOption: View {
    let title: String
    /// nil while nobody else is in the group, or Custom has no number.
    let hint: String?
    let selected: Bool
    let action: () -> Void

    init(title: String, hint: String?, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.hint = hint
        self.selected = selected
        self.action = action
    }

    private static let checkColumn: CGFloat = 20

    private var spoken: String {
        guard let line: String = hint else { return title }
        return title + ", " + line
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Gap.m) {
                Text(title)
                    .font(Fonts.body)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: Gap.s)
                if let line: String = hint {
                    Text(line)
                        .font(Fonts.body)
                        .monospacedDigit()
                        .foregroundStyle(Ink.text2)
                }
                check
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var check: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Ink.text)
            .opacity(selected ? 1 : 0)
            .frame(width: VoteRuleOption.checkColumn)
            .accessibilityHidden(true)
    }
}
