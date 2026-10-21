import SwiftUI

/// The owner picks how many of the others it takes to overrule a check-in or excuse. It opens on
/// tomorrow's rule, the one a save replaces: a change starts tomorrow, so no day already open to votes is
/// judged again. Saves, then closes; the store's toast says what changed.
struct VoteRuleSheet: View {
    let id: GroupID

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// nil until a row is tapped: the sheet shows tomorrow's rule.
    @State private var picked: VoteRule? = nil
    @State private var busy: Bool = false

    init(id: GroupID) {
        self.id = id
    }

    private var group: GroupInfo? {
        store.snapshots[id]?.group
    }

    /// Tomorrow's rule (a test group's tomorrow is the day after `testDay`).
    private var tomorrow: VoteRule {
        guard let g: GroupInfo = group else { return .majority }
        return Review.rule(forDay: DayClock.currentDay(g, now: Date()) + 1, group: g)
    }

    private var selection: VoteRule {
        picked ?? tomorrow
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

    var body: some View {
        SheetScaffold(title: "Overrule with", subtitle: subtitle, onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 0) {
                options
                FieldFooter("Changes start tomorrow. Days already being voted on keep their rule.")
            }
        } footer: {
            PillButton("Save", busy: busy, enabled: group != nil && selection != tomorrow, action: save)
        }
    }

    /// "{needed} needed" counts today's others; hidden while there are none.
    private var options: some View {
        let voters: Int = others
        return FormGroup {
            ForEach(VoteRule.allCases, id: \.self) { (rule: VoteRule) in
                if rule != VoteRule.allCases.first {
                    Hairline(leading: 16)
                }
                VoteRuleOption(rule: rule,
                               needed: voters > 0 ? rule.needed(voters: voters) : nil,
                               selected: rule == selection,
                               action: { pick(rule) })
            }
        }
    }

    private func pick(_ rule: VoteRule) {
        guard !busy else { return }
        picked = rule
    }

    private func save() {
        let rule: VoteRule = selection
        guard !busy, rule != tomorrow else { return }
        busy = true
        Task { @MainActor in
            await store.setVoteRule(rule, in: id)
            busy = false
            dismiss()
        }
    }
}

/// One rule: its title, how many it takes now, and a checkmark on the chosen one. One VoiceOver button:
/// "Two thirds, 3 needed", selected.
private struct VoteRuleOption: View {
    let rule: VoteRule
    /// nil while nobody else is in the group.
    let needed: Int?
    let selected: Bool
    let action: () -> Void

    init(rule: VoteRule, needed: Int?, selected: Bool, action: @escaping () -> Void) {
        self.rule = rule
        self.needed = needed
        self.selected = selected
        self.action = action
    }

    private static let checkColumn: CGFloat = 20

    private var neededText: String? {
        guard let n: Int = needed else { return nil }
        return "\(n) needed"
    }

    private var spoken: String {
        guard let count: String = neededText else { return VoteRuleText.title(rule) }
        return VoteRuleText.title(rule) + ", " + count
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Gap.m) {
                Text(VoteRuleText.title(rule))
                    .font(Fonts.body)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: Gap.s)
                if let count: String = neededText {
                    Text(count)
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
