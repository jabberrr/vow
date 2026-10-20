import SwiftUI

/// The Streak tab: your streak and when it began, the next milestone and your best, then a month
/// calendar of your vow days. Reads the store live on a per-minute clock, so today's ring and the day
/// rolling over stay on time. No horizontal gestures anywhere, so a vertical scroll always works.
struct StreakPage: View {
    let id: GroupID
    let metrics: StageMetrics
    let topToken: Int
    let onJoin: () -> Void

    @Environment(AppStore.self) private var store

    init(id: GroupID, metrics: StageMetrics, topToken: Int, onJoin: @escaping () -> Void) {
        self.id = id
        self.metrics = metrics
        self.topToken = topToken
        self.onJoin = onJoin
    }

    private static let topID: String = "streak-top"
    private static let pageTop: CGFloat = 18
    private static let sinceTop: CGFloat = 6
    private static let cardTop: CGFloat = 22

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .vowBackground()
    }

    // MARK: - Content

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let group: GroupInfo = store.snapshots[id]?.group, let summary: GroupSummary = store.summary(for: id) {
            page(group: group, summary: summary, now: now)
        } else {
            ProgressView()
                .tint(Ink.text3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func page(group: GroupInfo, summary: GroupSummary, now: Date) -> some View {
        ScrollViewReader { (proxy: ScrollViewProxy) in
            ScrollView(.vertical, showsIndicators: false) {
                column(group: group, summary: summary, now: now)
                    .padding(.horizontal, Gap.gutter)
                    .padding(.top, StreakPage.pageTop)
                    .padding(.bottom, Gap.xxl)
                    .id(StreakPage.topID)
            }
            .refreshable {
                await store.refreshAll()
            }
            .onChange(of: topToken) { _, _ in
                withAnimation(Anim.standard) {
                    proxy.scrollTo(StreakPage.topID, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func column(group: GroupInfo, summary: GroupSummary, now: Date) -> some View {
        if let viewer: MemberStanding = summary.viewer {
            memberColumn(group: group, summary: summary, viewer: viewer, now: now)
        } else {
            notMemberColumn(isFinished: summary.isFinished)
        }
    }

    private func memberColumn(group: GroupInfo, summary: GroupSummary, viewer: MemberStanding, now: Date) -> some View {
        VStack(spacing: 0) {
            flame(viewer.streak)
            if let line: String = sinceText(group: group, summary: summary, viewer: viewer) {
                note(line)
                    .padding(.top, StreakPage.sinceTop)
            }
            StreakStatsCard(viewer: viewer, isFinished: summary.isFinished)
                .padding(.top, StreakPage.cardTop)
            StreakCalendarView(group: group,
                               summary: summary,
                               standing: viewer,
                               atRisk: DayWindow.isAtRisk(group, now: now),
                               homeToken: topToken)
                .padding(.top, Gap.l)
        }
        .frame(maxWidth: .infinity)
    }

    /// A grey 0 and the one way in. A finished vow can't be joined any more, so it says so instead.
    private func notMemberColumn(isFinished: Bool) -> some View {
        VStack(spacing: 0) {
            flame(0)
            if isFinished {
                note("This vow has ended.")
                    .padding(.top, StreakPage.sinceTop)
            } else {
                PillButton("Write your vow to join", action: onJoin)
                    .padding(.top, Gap.xxl)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Not interactive here: this page is where the streak lives.
    private func flame(_ count: Int) -> some View {
        FlameStreak(count: count, size: metrics.compact ? .largeCompact : .large)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Fonts.subheadline)
            .foregroundStyle(Ink.text2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Derived

    /// "Since Oct 8" / "Since today"; "Final streak" once the vow is finished; nil without a streak.
    /// Today is the group's day, not the clock's, so a test group moved past real time still reads right.
    private func sinceText(group: GroupInfo, summary: GroupSummary, viewer: MemberStanding) -> String? {
        guard viewer.streak > 0 else { return nil }
        if summary.isFinished {
            return "Final streak"
        }
        guard let start: Date = StreakCalendar.streakStartDate(group: group, summary: summary, standing: viewer),
              let today: Date = DayClock.start(ofDay: summary.currentDay, group: group) else { return nil }
        return DayText.since(start, today: today, timeZoneID: group.timeZoneID)
    }
}
