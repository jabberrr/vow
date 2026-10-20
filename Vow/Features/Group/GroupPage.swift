import SwiftUI

/// Callbacks from the Group page to the shell, which owns the sheets and the confirmations.
struct GroupActions {
    let invite: () -> Void
    let editVow: () -> Void
    let showMember: (String) -> Void
    /// "Leave group": the shell asks first.
    let confirmLeave: () -> Void
    /// "Delete group" (the owner, who can't leave): the shell asks first.
    let confirmDelete: () -> Void
}

/// The Group tab: who is in the group (today's status, streak and net, Invite last), the group's points
/// and last day, your vow, then leave or delete. No test controls: they stay on Home's test bar, next
/// to the orb. Reads the store live on a per-minute clock, so your ring turns flame on time.
struct GroupPage: View {
    let id: GroupID
    /// Bumped when the selected tab is tapped again: scroll to the top.
    let topToken: Int
    let actions: GroupActions

    @Environment(AppStore.self) private var store

    init(id: GroupID, topToken: Int, actions: GroupActions) {
        self.id = id
        self.topToken = topToken
        self.actions = actions
    }

    private static let topID: String = "group-top"

    var body: some View {
        TimelineView(.everyMinute) { context in
            page(now: context.date)
        }
        .vowBackground()
    }

    // MARK: - Content

    @ViewBuilder
    private func page(now: Date) -> some View {
        if let group: GroupInfo = store.snapshots[id]?.group, let summary: GroupSummary = store.summary(for: id) {
            loaded(group: group, summary: summary, now: now)
        } else {
            ProgressView()
                .tint(Ink.text3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loaded(group: GroupInfo, summary: GroupSummary, now: Date) -> some View {
        ScrollViewReader { (proxy: ScrollViewProxy) in
            ScrollView(.vertical, showsIndicators: false) {
                column(group: group, summary: summary, now: now)
            }
            .refreshable {
                await store.refreshAll()
            }
            .onChange(of: topToken) { _, _ in
                withAnimation(Anim.standard) {
                    proxy.scrollTo(GroupPage.topID, anchor: .top)
                }
            }
        }
    }

    private func column(group: GroupInfo, summary: GroupSummary, now: Date) -> some View {
        let isMember: Bool = summary.viewer != nil
        return VStack(spacing: Gap.xxl) {
            GroupMembersCard(summary: summary,
                             viewerID: store.userID ?? "",
                             atRisk: DayWindow.isAtRisk(group, now: now),
                             canInvite: isMember && !summary.isFinished,
                             onSelect: actions.showMember,
                             onInvite: actions.invite)
            factsCard(GroupPage.facts(group: group, summary: summary, now: now))
            if !summary.isFinished {
                GroupActionRow(title: isMember ? "Edit vow" : "Write your vow",
                               systemImage: "pencil",
                               tint: Ink.text,
                               action: actions.editVow)
            }
            exitRow
        }
        .padding(.horizontal, Gap.gutter)
        .padding(.top, 14)
        .padding(.bottom, Gap.xxl)
        .id(GroupPage.topID)
    }

    // MARK: - Points

    private func factsCard(_ facts: [GroupFact]) -> some View {
        VStack(spacing: 0) {
            ForEach(facts) { (fact: GroupFact) in
                if fact.id != facts.first?.id {
                    Hairline(leading: Gap.l)
                }
                GroupFactRow(fact: fact)
            }
        }
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    /// Daily stake; Pot only while one carries over (> 0 after rounding); Forfeited; with an end date,
    /// "Last day" ("Ended" once it has passed) as "Oct 30", or "Day 30" in a test group.
    private static func facts(group: GroupInfo, summary: GroupSummary, now: Date) -> [GroupFact] {
        var out: [GroupFact] = []
        out.append(GroupFact(title: "Daily stake",
                             value: StakeText.amount(group.stake),
                             spokenValue: PointsText.spoken(Double(group.stake)),
                             tint: Ink.text2))
        if (summary.pot * 100).rounded() > 0 {
            out.append(GroupFact(title: "Pot",
                                 value: PointsText.string(summary.pot),
                                 spokenValue: PointsText.spoken(summary.pot),
                                 tint: Ink.gain))
        }
        out.append(GroupFact(title: "Forfeited",
                             value: PointsText.string(summary.totalForfeited),
                             spokenValue: PointsText.spoken(summary.totalForfeited),
                             tint: Ink.text2))
        if let last: String = DayText.finalDay(group, now: now) {
            out.append(GroupFact(title: summary.isFinished ? "Ended" : "Last day",
                                 value: last,
                                 spokenValue: last,
                                 tint: Ink.text2))
        }
        return out
    }

    // MARK: - Leave or delete

    /// The owner can't leave (the store refuses); they delete the group instead.
    private var exitRow: some View {
        let isOwner: Bool = store.isOwner(id)
        return GroupActionRow(title: isOwner ? "Delete group" : "Leave group",
                              systemImage: isOwner ? "trash" : "rectangle.portrait.and.arrow.right",
                              tint: Ink.loss,
                              action: isOwner ? actions.confirmDelete : actions.confirmLeave)
    }
}

/// One row of the group's points card: title on the left, value on the right; stacked at
/// accessibility sizes. One VoiceOver element ("Pot, 4 points").
private struct GroupFactRow: View {
    let fact: GroupFact

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize: DynamicTypeSize

    init(fact: GroupFact) {
        self.fact = fact
    }

    var body: some View {
        content
            .padding(.horizontal, Gap.l)
            .padding(.vertical, Gap.m)
            .frame(minHeight: 50)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fact.title)
            .accessibilityValue(fact.spokenValue)
    }

    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Gap.xxs) {
                title
                value
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
                title
                Spacer(minLength: Gap.s)
                value
            }
        }
    }

    private var title: some View {
        Text(fact.title)
            .font(Fonts.body)
            .foregroundStyle(Ink.text)
    }

    private var value: some View {
        Text(fact.value)
            .font(Fonts.body)
            .monospacedDigit()
            .foregroundStyle(fact.tint)
            .layoutPriority(1)
    }
}

/// A single action in its own card: "Edit vow", "Leave group", "Delete group".
private struct GroupActionRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    init(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Fonts.body)
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Gap.l)
            .padding(.vertical, Gap.m)
            .frame(minHeight: 50)
        }
        .buttonStyle(RowPressStyle())
        .cardSurface()
    }
}

/// One fact about the group's points or end.
private struct GroupFact: Identifiable {
    let title: String
    let value: String
    let spokenValue: String
    let tint: Color

    var id: String { title }
}
