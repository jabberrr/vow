import SwiftUI

/// The Activity tab: every ledger line by day, newest first, ranked within each day. Until a day has
/// settled it opens with when days close. No title of its own (the tab says it). Reads the store live,
/// on a per-minute clock so "Today" and "Yesterday" move on at midnight.
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
        return ScrollViewReader { (proxy: ScrollViewProxy) in
            ScrollView(.vertical, showsIndicators: false) {
                column(group: group, days: days, waiting: waiting)
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
    private func column(group: GroupInfo, days: [ActivityDay], waiting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if waiting {
                emptyCard(group)
            }
            ForEach(days) { (day: ActivityDay) in
                daySection(day)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Gap.gutter)
        .padding(.top, 10)
        .padding(.bottom, Gap.xxl)
        .id(ActivityPage.topID)
    }

    private func daySection(_ day: ActivityDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.title)
                .font(Fonts.subheadlineSemibold)
                .foregroundStyle(Ink.text2)
                .padding(.horizontal, Gap.xs)
                .accessibilityAddTraits(.isHeader)
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

    /// Some line belongs to a day before today (today's joins don't count).
    private static func hasSettledDay(_ summary: GroupSummary) -> Bool {
        return summary.ledger.contains { (line: LedgerLine) -> Bool in line.day < summary.currentDay }
    }
}
