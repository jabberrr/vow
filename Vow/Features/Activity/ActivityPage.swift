import SwiftUI

/// The Activity tab: every ledger line by day, newest first, ranked within each day. Until a day has
/// settled it opens with when days close. While the group can still vote on yesterday, its heading says
/// so: its lines can still change. No title of its own (the tab says it). Reads the store live, on a
/// per-minute clock so "Today" and "Yesterday" move on at midnight.
struct ActivityPage: View {
    let id: GroupID
    /// Bumped when the selected tab is tapped again: scroll to the top.
    let topToken: Int

    @Environment(AppStore.self) private var store

    init(id: GroupID, topToken: Int) {
        self.id = id
        self.topToken = topToken
    }

    private static let topID: String = "activity-top"

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
        let days: [ActivityDay] = LedgerFormat.days(summary.ledger, group: group, currentDay: titleDay)
        let waiting: Bool = !summary.isFinished && !ActivityPage.hasSettledDay(summary)
        let voting: Int? = ActivityPage.votingDay(group: group, summary: summary, now: now)
        return ScrollViewReader { (proxy: ScrollViewProxy) in
            ScrollView(.vertical, showsIndicators: false) {
                column(group: group, days: days, waiting: waiting, votingDay: voting)
            }
            .refreshable {
                await store.refreshAll()
            }
            .onChange(of: topToken) { _, _ in
                withAnimation(Anim.standard) {
                    proxy.scrollTo(ActivityPage.topID, anchor: .top)
                }
            }
        }
    }

    /// `waiting`: no day has settled yet; the empty card comes first and today's joins follow it.
    /// `votingDay`: the settled day the group can still vote on.
    private func column(group: GroupInfo, days: [ActivityDay], waiting: Bool, votingDay: Int?) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if waiting {
                emptyCard(group)
            }
            ForEach(days) { (day: ActivityDay) in
                daySection(day, votesOpen: day.day == votingDay)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Gap.gutter)
        .padding(.top, 10)
        .padding(.bottom, Gap.xxl)
        .id(ActivityPage.topID)
    }

    private func daySection(_ day: ActivityDay, votesOpen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            dayHeader(day, votesOpen: votesOpen)
            VStack(spacing: 0) {
                ForEach(day.lines) { (line: LedgerLine) in
                    LedgerRow(line: line)
                }
            }
            .padding(.vertical, Gap.xs)
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
    }

    /// "Yesterday", with "Votes still open" trailing while its numbers can still change. One VoiceOver
    /// header: "Yesterday, votes still open".
    private func dayHeader(_ day: ActivityDay, votesOpen: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
            Text(day.title)
                .font(Fonts.subheadlineSemibold)
                .foregroundStyle(Ink.text2)
            if votesOpen {
                Spacer(minLength: Gap.s)
                Text("Votes still open")
                    .font(Fonts.footnote)
                    .foregroundStyle(Ink.text3)
            }
        }
        .padding(.horizontal, Gap.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(votesOpen ? day.title + ", votes still open" : day.title)
        .accessibilityAddTraits(.isHeader)
    }

    private func emptyCard(_ group: GroupInfo) -> some View {
        Text(emptyMessage(group))
            .font(Fonts.subheadline)
            .foregroundStyle(Ink.text3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Gap.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
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
    /// the final day would read "Yesterday" forever; the group's clock moves on instead ("Oct 30" from
    /// the second day after it). A test group's clock stops there (Next day is off once it is
    /// finished), so its days count from one further and every title reads "Day N".
    private static func titleDay(group: GroupInfo, summary: GroupSummary, now: Date) -> Int {
        guard summary.isFinished else { return summary.currentDay }
        // Never behind the summary (the timeline's minute can trail the store's clock at midnight).
        let clockDay: Int = max(summary.currentDay, DayClock.currentDay(group, now: now))
        return group.isTest ? max(clockDay, summary.currentDay + 1) : clockDay
    }

    /// Yesterday while the group can still vote on it (until tonight ends), in a group with someone to vote:
    /// the only settled day whose lines can still change. A finished vow's final day takes votes through
    /// the day after it.
    private static func votingDay(group: GroupInfo, summary: GroupSummary, now: Date) -> Int? {
        let day: Int = summary.currentDay - 1
        guard summary.standings.count >= 2, day >= 0, Review.isOpen(day: day, group: group, now: now) else { return nil }
        return day
    }

    /// Some line belongs to a day before today (today's joins don't count).
    private static func hasSettledDay(_ summary: GroupSummary) -> Bool {
        return summary.ledger.contains { (line: LedgerLine) -> Bool in line.day < summary.currentDay }
    }
}
