import SwiftUI

/// One member (or you, with Edit vow): their vow, today's status, streak, best and net. Only your own
/// net is coloured. Reads the store live.
struct MemberSheet: View {
    let id: GroupID
    let userID: String
    let onEditVow: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(id: GroupID, userID: String, onEditVow: @escaping () -> Void) {
        self.id = id
        self.userID = userID
        self.onEditVow = onEditVow
    }

    var body: some View {
        let summary: GroupSummary? = store.summary(for: id)
        let member: MemberStanding? = summary?.standings.first(where: { (s: MemberStanding) -> Bool in s.userID == userID })
        return ScrollView(.vertical, showsIndicators: false) {
            content(summary, member)
                .padding(.horizontal, Gap.gutter)
                .padding(.top, 22)
                .padding(.bottom, Gap.xxl)
        }
        .background(Ink.sheet.ignoresSafeArea())
    }

    @ViewBuilder
    private func content(_ summary: GroupSummary?, _ member: MemberStanding?) -> some View {
        if let s = summary, let m = member {
            MemberDetails(summary: s,
                          member: m,
                          isYou: s.viewer?.userID == m.userID,
                          onClose: { dismiss() },
                          onEditVow: onEditVow)
        } else {
            HStack {
                Spacer(minLength: 0)
                SheetCloseButton(action: { dismiss() })
                    .padding(.trailing, -8)
            }
        }
    }
}

/// The sheet's content for a member who is in the group.
private struct MemberDetails: View {
    let summary: GroupSummary
    let member: MemberStanding
    let isYou: Bool
    let onClose: () -> Void
    let onEditVow: () -> Void

    private var name: String {
        isYou ? "You" : MemberText.name(member.displayName)
    }

    /// The whole vow: on their own sheet the "I will" is read as written.
    private var vow: String {
        member.vow
    }

    /// As on the stage: "I will" in text2, the rest in text.
    private var vowText: Text {
        let parts: (prefix: String, verb: String, suffix: String) = VowText.split(vow)
        if parts.verb.isEmpty {
            return Text(vow).foregroundStyle(Ink.text)
        }
        let head: Text = Text(parts.prefix).foregroundStyle(Ink.text2)
        let rest: Text = Text(parts.verb + parts.suffix).foregroundStyle(Ink.text)
        return head + rest
    }

    /// nil once the vow is finished: there is no today to report.
    private var today: MemberDay? {
        summary.isFinished ? nil : MemberDay.of(member, isViewer: isYou)
    }

    private var state: SphereState {
        today?.sphere ?? .unlit
    }

    private var spokenValue: String {
        var parts: [String] = []
        if !vow.isEmpty {
            parts.append(vow)
        }
        if let day: MemberDay = today {
            parts.append(day.title)
        }
        return parts.joined(separator: ", ")
    }

    /// A finished vow can't be edited (the store refuses), so the button goes with it.
    private var canEditVow: Bool {
        isYou && !summary.isFinished
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if canEditVow {
                PillButton("Edit vow", systemImage: "pencil", kind: .secondary, compact: true, action: onEditVow)
                    .padding(.top, 14)
                    .padding(.leading, 70)
            }
            stats
                .padding(.top, 22)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Sphere(theme: Overview.theme(summary),
                   state: state,
                   size: 56,
                   initial: NameFormat.initial(member.displayName))
                .animation(Anim.light, value: state)
            nameColumn
            SheetCloseButton(action: onClose)
                .padding(.trailing, -8)
        }
    }

    private var nameColumn: some View {
        VStack(alignment: .leading, spacing: Gap.xxs) {
            Text(name)
                .font(Fonts.title2)
                .foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            if !vow.isEmpty {
                vowText
                    .font(Fonts.subheadline)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(spokenValue)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Stats

    private var stats: some View {
        HStack(spacing: 0) {
            streakColumn
            statDivider
            bestColumn
            statDivider
            netColumn
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .cardSurface()
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(width: 1)
            .accessibilityHidden(true)
    }

    private var streakColumn: some View {
        statColumn(label: "Streak", spokenLabel: "Streak", spokenValue: DayText.count(member.streak)) {
            FlameStreak(count: member.streak, size: .medium)
        }
    }

    private var bestColumn: some View {
        statColumn(label: "Best", spokenLabel: "Best", spokenValue: DayText.count(member.bestStreak)) {
            Text("\(member.bestStreak)")
                .font(Fonts.stat)
                .monospacedDigit()
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Your net in points colour; everyone else's in text2 (no red on friends).
    private var netColumn: some View {
        statColumn(label: "Net pts", spokenLabel: "Net", spokenValue: MemberText.netSpoken(member.net)) {
            Text(MemberText.netNumber(member.net))
                .font(Fonts.stat)
                .monospacedDigit()
                .foregroundStyle(isYou ? Ink.points(member.net) : Ink.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func statColumn<Value: View>(label: String,
                                          spokenLabel: String,
                                          spokenValue: String,
                                          @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: Gap.xs) {
            value()
            Text(label)
                .font(Fonts.footnote)
                .foregroundStyle(Ink.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, Gap.xs)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(spokenValue)
    }
}
