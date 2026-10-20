import SwiftUI
import Accessibility

/// A calm month view of your vow days with one accent: every kept day shares the streak's flame tint
/// (so the eye reads runs and gaps, not colours), a miss is a small dot, today is a ring, upcoming days
/// are plain dates and the final day carries a flag. ‹ › are the only way to change month: a horizontal
/// drag would fight the page's vertical scroll. Always six week rows, so the card keeps one height.
struct StreakCalendarView: View {
    let group: GroupInfo
    let summary: GroupSummary
    let standing: MemberStanding
    /// The last 4 h of a real group's day: today's open ring turns flame.
    let atRisk: Bool
    /// Each change returns to today's month (re-tapping the Streak tab).
    let homeToken: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    /// The month picked with ‹ › (its start); nil = the home month (today's, or the final day's).
    @State private var picked: Date? = nil
    /// The months between renders; a reference, so filling it never re-renders.
    @State private var memo: CalendarMemo = CalendarMemo()

    init(group: GroupInfo, summary: GroupSummary, standing: MemberStanding, atRisk: Bool, homeToken: Int) {
        self.group = group
        self.summary = summary
        self.standing = standing
        self.atRisk = atRisk
        self.homeToken = homeToken
    }

    private static let weeks: Int = 6
    private static let rowGap: CGFloat = 6
    private static let headerHeight: CGFloat = 48
    private static let gridTop: CGFloat = 10
    private static let bottomPadding: CGFloat = 14
    private static let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        content(memo.list(group: group, summary: summary, standing: standing, device: Calendar.current))
            .onChange(of: homeToken) { _, _ in
                show(nil)
            }
    }

    @ViewBuilder
    private func content(_ list: MonthList) -> some View {
        if list.months.isEmpty {
            EmptyView()
        } else {
            card(list, index: shownIndex(list))
        }
    }

    /// Capped at xxLarge: the 7-column geometry is fixed (each day shows the Large Content Viewer).
    private func card(_ list: MonthList, index: Int) -> some View {
        let month: CalendarMonth = list.months[index]
        return VStack(spacing: 0) {
            header(list, index: index)
            weekdayRow(list.weekdays)
                .padding(.top, Gap.xxs)
            ZStack {
                grid(month)
                    .id(month.id)
                    .transition(.opacity)
            }
            .padding(.top, StreakCalendarView.gridTop)
        }
        .padding(.top, Gap.xs)
        .padding(.horizontal, Gap.m)
        .padding(.bottom, StreakCalendarView.bottomPadding)
        .frame(maxWidth: .infinity)
        .cardSurface()
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    // MARK: - Header

    private func header(_ list: MonthList, index: Int) -> some View {
        HStack(spacing: 0) {
            chevron("chevron.left", label: "Previous month", enabled: index > 0) {
                step(list, to: index - 1)
            }
            Text(DayText.month(list.months[index].start, timeZoneID: group.timeZoneID))
                .font(Fonts.headline)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            chevron("chevron.right", label: "Next month", enabled: index < list.months.count - 1) {
                step(list, to: index + 1)
            }
        }
        .frame(minHeight: StreakCalendarView.headerHeight)
    }

    private func chevron(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ink.text)
                .frame(width: Gap.hit, height: Gap.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: systemImage)
        }
    }

    // MARK: - Grid

    private func weekdayRow(_ symbols: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<symbols.count, id: \.self) { (column: Int) in
                Text(symbols[column])
                    .font(Fonts.captionBold)
                    .foregroundStyle(Ink.text3)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// Blanks before day 1, one cell per date, then blanks up to six full weeks.
    private func grid(_ month: CalendarMonth) -> some View {
        LazyVGrid(columns: StreakCalendarView.columns, spacing: StreakCalendarView.rowGap) {
            ForEach(0..<(7 * StreakCalendarView.weeks), id: \.self) { (slot: Int) in
                slotView(slot, month: month)
            }
        }
    }

    @ViewBuilder
    private func slotView(_ slot: Int, month: CalendarMonth) -> some View {
        let index: Int = slot - month.leadingBlanks
        if index >= 0 && index < month.days.count {
            DayCell(day: month.days[index],
                    spoken: memo.spoken(month.days[index].date, timeZoneID: group.timeZoneID),
                    atRisk: atRisk)
        } else {
            Color.clear
                .frame(height: DayCell.size)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Months

    private func shownIndex(_ list: MonthList) -> Int {
        guard let start: Date = picked else { return list.home }
        for index in list.months.indices where list.months[index].start == start {
            return index
        }
        return list.home
    }

    /// ‹ ›: cross-fade to the month and say which one it is (VoiceOver focus stays on the chevron).
    private func step(_ list: MonthList, to index: Int) {
        guard index >= 0 && index < list.months.count else { return }
        let month: CalendarMonth = list.months[index]
        show(index == list.home ? nil : month.start)
        AccessibilityNotification.Announcement(DayText.month(month.start, timeZoneID: group.timeZoneID)).post()
    }

    /// Reduce Motion: the month swaps without a fade.
    private func show(_ start: Date?) {
        withAnimation(reduceMotion ? nil : Anim.fade) {
            picked = start
        }
    }
}

// MARK: - Day cell

/// One date: its number centred in a 36 pt circle.
private struct DayCell: View {
    let day: CalendarDay
    /// "October 8".
    let spoken: String
    let atRisk: Bool

    static let size: CGFloat = 36
    private static let flagOffset: CGFloat = 14
    private static let dot: CGFloat = 4
    private static let outsideOpacity: Double = 0.45

    private var isToday: Bool {
        day.state == .todayOpen || day.state == .todayKept
    }

    /// Outside dates are only layout (the final day is never one, but keep it reachable if it were).
    private var isVowDay: Bool {
        day.state != .outside || day.isFinal
    }

    var body: some View {
        Text("\(day.dayNumber)")
            .font(isToday ? Fonts.subheadlineSemibold : Fonts.subheadline)
            .monospacedDigit()
            .foregroundStyle(numberColor)
            .opacity(day.state == .outside ? DayCell.outsideOpacity : 1)
            .frame(width: DayCell.size, height: DayCell.size)
            .background {
                fill
            }
            .overlay {
                ring
            }
            .overlay(alignment: .bottom) {
                missDot
            }
            .overlay {
                flag
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityValue(value)
            .accessibilityHidden(!isVowDay)
            .accessibilityShowsLargeContentViewer {
                Text(value.isEmpty ? spoken : spoken + ", " + value)
            }
    }

    private var numberColor: Color {
        switch day.state {
        case .kept, .todayKept, .todayOpen:
            return Ink.text
        case .upcoming:
            return Ink.text2
        case .missed, .outside:
            return Ink.text3
        }
    }

    /// Every kept day the same flat flame tint (the milestone tag's look).
    @ViewBuilder
    private var fill: some View {
        switch day.state {
        case .kept, .todayKept:
            Circle()
                .fill(Ink.flameTint)
        case .todayOpen, .missed, .upcoming, .outside:
            Color.clear
        }
    }

    /// Kept: the tint's edge. Today: a ring (flame in the last 4 h while still open).
    @ViewBuilder
    private var ring: some View {
        switch day.state {
        case .kept:
            Circle()
                .strokeBorder(Ink.flameEdge, lineWidth: 1)
        case .todayKept:
            Circle()
                .strokeBorder(Ink.text, lineWidth: 1.5)
        case .todayOpen:
            Circle()
                .strokeBorder(atRisk ? Ink.flame : Ink.text, lineWidth: 1.5)
        case .missed, .upcoming, .outside:
            EmptyView()
        }
    }

    /// A miss is visible but quiet: a small dot, no red fill.
    @ViewBuilder
    private var missDot: some View {
        if day.state == .missed {
            Circle()
                .fill(Ink.loss)
                .frame(width: DayCell.dot, height: DayCell.dot)
                .padding(.bottom, DayCell.dot)
        }
    }

    /// The finish line, past or to come, at the circle's top-right.
    @ViewBuilder
    private var flag: some View {
        if day.isFinal {
            Image(systemName: "flag.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.text)
                .offset(x: DayCell.flagOffset, y: -DayCell.flagOffset)
        }
    }

    /// "kept", "missed", "today, your turn", "today, kept", "to come", plus ", last day" on the final day.
    private var value: String {
        var text: String
        switch day.state {
        case .kept:
            text = "kept"
        case .missed:
            text = "missed"
        case .todayOpen:
            text = "today, your turn"
        case .todayKept:
            text = "today, kept"
        case .upcoming:
            text = "to come"
        case .outside:
            text = ""
        }
        if day.isFinal {
            text = text.isEmpty ? "last day" : text + ", last day"
        }
        return text
    }
}

// MARK: - Memo

/// What the card shows for one summary.
private struct MonthList {
    /// Oldest first.
    let months: [CalendarMonth]
    /// Today's month; without a today (a finished vow) the last one, which holds the final day.
    let home: Int
    /// Very short weekday names starting on the device's first weekday ("S M T W T F S").
    let weekdays: [String]

    static let empty: MonthList = MonthList(months: [], home: 0, weekdays: [])
}

/// Everything `StreakCalendar.months` reads.
private struct CalendarKey: Equatable {
    let group: GroupInfo
    let summary: GroupSummary
    let standing: MemberStanding
    let firstWeekday: Int
}

/// One `StreakCalendar.months` pass per change of the summary (not per render), and the cells' spoken
/// dates, each formatted once.
private final class CalendarMemo {
    private var key: CalendarKey? = nil
    private var value: MonthList = MonthList.empty
    private var spokenDates: [Date: String] = [:]

    /// Dates follow the group's day clock; only the week's first day comes from the device.
    func list(group: GroupInfo, summary: GroupSummary, standing: MemberStanding, device: Calendar) -> MonthList {
        let fresh: CalendarKey = CalendarKey(group: group, summary: summary, standing: standing,
                                             firstWeekday: device.firstWeekday)
        if let current: CalendarKey = key, current == fresh {
            return value
        }
        if key?.group.timeZoneID != group.timeZoneID {
            spokenDates = [:]
        }
        key = fresh
        var calendar: Calendar = DayClock.calendar(group.timeZoneID)
        calendar.firstWeekday = device.firstWeekday
        let months: [CalendarMonth] = StreakCalendar.months(group: group, summary: summary, standing: standing,
                                                            calendar: calendar)
        value = MonthList(months: months,
                          home: CalendarMemo.homeIndex(months),
                          weekdays: CalendarMemo.weekdays(device))
        return value
    }

    /// "October 8" in the group's time zone.
    func spoken(_ date: Date, timeZoneID: String) -> String {
        if let cached: String = spokenDates[date] {
            return cached
        }
        let text: String = DayText.spoken(date, timeZoneID: timeZoneID)
        spokenDates[date] = text
        return text
    }

    private static func homeIndex(_ months: [CalendarMonth]) -> Int {
        for index in months.indices.reversed() {
            for day in months[index].days where day.state == .todayOpen || day.state == .todayKept {
                return index
            }
        }
        return max(0, months.count - 1)
    }

    /// The symbols start on Sunday; rotate them by firstWeekday − 1 (Monday-first: "M T W T F S S").
    private static func weekdays(_ device: Calendar) -> [String] {
        let symbols: [String] = device.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let shift: Int = device.firstWeekday - 1
        var out: [String] = []
        for column in 0..<7 {
            out.append(symbols[(column + shift) % 7])
        }
        return out
    }
}
