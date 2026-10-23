import SwiftUI

/// The Activity tab: one continuous list of the group's days, newest first, each under a small header and
/// split from the next by a hairline, with no cards. Each stake lost is followed by an arrow line for each
/// keeper who got a part of it (`ActivityFeed`). Until a day has settled it opens with when days close. While
/// the group can still vote on yesterday, its header says so: its points can still change. No title of its
/// own (the tab says it). A new group's few days hold still, but for a pull to refresh (`PageScroll`). Reads
/// the store live, on a per-minute clock so "Today" and "Yesterday" move on at midnight.
struct ActivityPage: View {
    let id: GroupID
    /// Bumped when the selected tab is tapped again: scroll to the top.
    let topToken: Int

    @Environment(AppStore.self) private var store

    /// Below the last day: empty margin, so the page may lose it under the tab bar and still hold still.
    private static let bottomMargin: CGFloat = Gap.xxl

    init(id: GroupID, topToken: Int) {
        self.id = id
        self.topToken = topToken
    }

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
        let titleDay: Int = ActivityPage.titleDay(group: group, summary: summary, now: now)
        let votingDay: Int? = ActivityPage.votingDay(group: group, summary: summary, now: now)
        let sections: [ActivitySection] = ActivityFeed.build(summary.days, group: group, viewerID: store.userID ?? "",
                                                             titleDay: titleDay, votingDay: votingDay, now: now)
        let waiting: Bool = !summary.isFinished && !ActivityPage.hasSettledDay(summary)
        return PageScroll(topToken: topToken, slack: ActivityPage.bottomMargin, onRefresh: { await store.refreshAll() }) {
            column(group: group, sections: sections, waiting: waiting)
        }
    }

    /// `waiting`: no day has settled yet; the note comes first and today's joins follow it. Lazy, because a
    /// long-running group lists up to `Settlement.dayCap` days.
    private func column(group: GroupInfo, sections: [ActivitySection], waiting: Bool) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if waiting {
                emptyNote(group)
            }
            ForEach(sections) { (section: ActivitySection) in
                if waiting || section.id != sections.first?.id {
                    Hairline(leading: 0)
                        .padding(.vertical, Gap.l)
                }
                ActivityDayView(section: section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Gap.gutter)
        .padding(.top, Gap.l)
        .padding(.bottom, ActivityPage.bottomMargin)
    }

    private func emptyNote(_ group: GroupInfo) -> some View {
        Text(emptyMessage(group))
            .font(Fonts.subheadline)
            .foregroundStyle(Ink.text3)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A test group's days close when its owner taps Next day on Home's test bar.
    private func emptyMessage(_ group: GroupInfo) -> String {
        if !group.isTest {
            return "Nothing settled yet. Days close at midnight."
        }
        if store.testingMode && store.isOwner(id) {
            return "Nothing settled yet. Tap Next day to close today."
        }
        return "Nothing settled yet. The owner moves the days."
    }

    // MARK: - Days

    /// The day the titles count from. A finished vow's summary stops at the day after its final day, so
    /// the final day would read "Yesterday" forever; the group's clock moves on instead ("Fri, Oct 30"
    /// from the second day after it). A test group's clock stops there (Next day is off once it is
    /// finished), so its days count from one further and every title reads "Day N".
    private static func titleDay(group: GroupInfo, summary: GroupSummary, now: Date) -> Int {
        guard summary.isFinished else { return summary.currentDay }
        // Never behind the summary (the timeline's minute can trail the store's clock at midnight).
        let clockDay: Int = max(summary.currentDay, DayClock.currentDay(group, now: now))
        return group.isTest ? max(clockDay, summary.currentDay + 1) : clockDay
    }

    /// Yesterday while the group can still vote on it (until tonight ends), in a group with someone to vote:
    /// the only settled day whose points can still change. A finished vow's final day takes votes through
    /// the day after it.
    private static func votingDay(group: GroupInfo, summary: GroupSummary, now: Date) -> Int? {
        let day: Int = summary.currentDay - 1
        guard summary.standings.count >= 2, day >= 0, Review.isOpen(day: day, group: group, now: now) else { return nil }
        return day
    }

    /// Some day has closed (today's joins don't count).
    private static func hasSettledDay(_ summary: GroupSummary) -> Bool {
        return summary.days.contains { (day: LedgerDay) -> Bool in day.isClosed }
    }
}
