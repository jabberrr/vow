import SwiftUI
import Accessibility

/// A calm month view of your vow days with one accent, the streak's flame. Kept days are filled with its
/// gradient, and a run of them joins into one band that ends at a week row's edge and picks up again at
/// the start of the next row, so every row holds whole capsules. A miss is a quiet grey disc, today is a
/// ring, days to come are plain dates and the final day carries a flag. ‹ › page from the month the group
/// began to a year past this one (or the final day's month, if later), and are the only way to change
/// month: a horizontal drag would fight the page's vertical scroll. Always six week rows, so the card
/// keeps one height.
struct StreakCalendarView: View {
    let group: GroupInfo
    let summary: GroupSummary
    let standing: MemberStanding
    /// Places the current month: a finished vow's summary stops at its final day, the clock doesn't.
    let now: Date
    /// The last 4 h of a real group's day: today's open ring turns flame.
    let atRisk: Bool
    /// Each change returns to the home month (re-tapping the Streak tab).
    let homeToken: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    /// The month picked with ‹ › (its index in the span); nil = the home month (today's, or the final day's).
    @State private var picked: Int? = nil
    /// The span and its laid-out months between renders; a reference, so filling it never re-renders.
    @State private var memo: CalendarMemo = CalendarMemo()

    init(group: GroupInfo, summary: GroupSummary, standing: MemberStanding, now: Date, atRisk: Bool, homeToken: Int) {
        self.group = group
        self.summary = summary
        self.standing = standing
        self.now = now
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
        content(memo.span(group: group, summary: summary, standing: standing, device: Calendar.current, now: now))
            .onChange(of: homeToken) { _, _ in
                show(nil)
            }
    }

    @ViewBuilder
    private func content(_ span: CalendarSpan?) -> some View {
        if let span: CalendarSpan = span {
            let index: Int = shownIndex(span)
            if let month: CalendarMonth = memo.month(at: index) {
                card(span, month: month, index: index)
            }
        }
    }

    /// Capped at xxLarge: the 7-column geometry is fixed (each day shows the Large Content Viewer).
    private func card(_ span: CalendarSpan, month: CalendarMonth, index: Int) -> some View {
        VStack(spacing: 0) {
            header(span, month: month, index: index)
            weekdayRow(memo.weekdays)
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

    /// ‹ and › disable at the span's ends: the group's first month, and the last one ahead.
    private func header(_ span: CalendarSpan, month: CalendarMonth, index: Int) -> some View {
        HStack(spacing: 0) {
            chevron("chevron.left", label: "Previous month", enabled: index > 0) {
                step(span, to: index - 1)
            }
            Text(DayText.month(month.start, timeZoneID: group.timeZoneID))
                .font(Fonts.headline)
                .foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            chevron("chevron.right", label: "Next month", enabled: index < span.count - 1) {
                step(span, to: index + 1)
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

    /// Blanks before day 1, one cell per date, then blanks up to six full weeks. No column spacing, so a
    /// run's band passes from cell to cell unbroken.
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

    private func shownIndex(_ span: CalendarSpan) -> Int {
        guard let index: Int = picked else { return span.home }
        return min(max(0, index), span.count - 1)
    }

    /// ‹ ›: cross-fade to the month and say which one it is (VoiceOver focus stays on the chevron).
    private func step(_ span: CalendarSpan, to index: Int) {
        guard index >= 0 && index < span.count, let month: CalendarMonth = memo.month(at: index) else { return }
        show(index == span.home ? nil : index)
        AccessibilityNotification.Announcement(DayText.month(month.start, timeZoneID: group.timeZoneID)).post()
    }

    /// Reduce Motion: the month swaps without a fade.
    private func show(_ index: Int?) {
        withAnimation(reduceMotion ? nil : Anim.fade) {
            picked = index
        }
    }
}

// MARK: - Day cell

/// One date: its number centred in a 36 pt disc, on the band of a run of kept days.
private struct DayCell: View {
    let day: CalendarDay
    /// "October 8".
    let spoken: String
    let atRisk: Bool

    static let size: CGFloat = 36
    /// A joining band reaches this far past its cell, so neighbours overlap instead of leaving a seam.
    private static let seamOverlap: CGFloat = 0.5
    private static let ringWidth: CGFloat = 1.5
    /// Today kept: the ring sits inside the disc, clear of the band.
    private static let keptRingInset: CGFloat = 3
    private static let flagOffset: CGFloat = 14
    private static let flagBadge: CGFloat = 18
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
                disc
            }
            .overlay {
                ring
            }
            .overlay {
                flag
            }
            .frame(maxWidth: .infinity)
            .background {
                band
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityValue(value)
            .accessibilityHidden(!isVowDay)
            .accessibilityShowsLargeContentViewer {
                Text(value.isEmpty ? spoken : spoken + ", " + value)
            }
    }

    /// Dark ink on the flame, readable grey on a miss; days to come plain, outside dates dim.
    private var numberColor: Color {
        switch day.state {
        case .kept, .todayKept:
            return Ink.onFlame
        case .todayOpen:
            return Ink.text
        case .missed, .upcoming:
            return Ink.text2
        case .outside:
            return Ink.text3
        }
    }

    /// Kept: the flame gradient, top to bottom like the streak's flame. Missed: grey, never red.
    @ViewBuilder
    private var disc: some View {
        switch day.state {
        case .kept, .todayKept:
            Circle()
                .fill(Ink.flameGradient)
        case .missed:
            Circle()
                .fill(Ink.missedDay)
        case .todayOpen, .upcoming, .outside:
            Color.clear
        }
    }

    /// From the centre to each side that joins a kept neighbour, the disc's height and gradient: the discs
    /// and bands of a run make one capsule. A row's edge never joins (see `CalendarDay.joinsNext`).
    private var band: some View {
        HStack(spacing: 0) {
            bandHalf(day.joinsPrevious)
            bandHalf(day.joinsNext)
        }
        .frame(height: DayCell.size)
        .padding(.horizontal, -DayCell.seamOverlap)
    }

    @ViewBuilder
    private func bandHalf(_ joins: Bool) -> some View {
        if joins {
            Rectangle()
                .fill(Ink.flameGradient)
        } else {
            Color.clear
        }
    }

    /// Today: a ring, flame in the last 4 h while still open. Once kept, a dark ring inside the flame disc.
    @ViewBuilder
    private var ring: some View {
        switch day.state {
        case .todayOpen:
            Circle()
                .strokeBorder(atRisk ? Ink.flame : Ink.text, lineWidth: DayCell.ringWidth)
        case .todayKept:
            Circle()
                .strokeBorder(Ink.onFlame, lineWidth: DayCell.ringWidth)
                .padding(DayCell.keptRingInset)
        case .kept, .missed, .upcoming, .outside:
            EmptyView()
        }
    }

    /// The finish line, past or to come, at the disc's top-right. Its badge is the card's colour, so the
    /// flag reads on a flame or grey disc as well as on the bare card.
    @ViewBuilder
    private var flag: some View {
        if day.isFinal {
            Image(systemName: "flag.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Ink.text)
                .frame(width: DayCell.flagBadge, height: DayCell.flagBadge)
                .background(Circle().fill(Ink.card))
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

/// Everything `CalendarSpan` reads (`now` only through the clock's day).
private struct CalendarKey: Equatable {
    let group: GroupInfo
    let summary: GroupSummary
    let standing: MemberStanding
    let firstWeekday: Int
    let clockDay: Int
}

/// One `CalendarSpan` per change of the summary or the day (not per render), each month laid out the
/// first time it is shown, and the cells' spoken dates, each formatted once.
private final class CalendarMemo {
    /// Very short weekday names starting on the device's first weekday ("S M T W T F S").
    private(set) var weekdays: [String] = []
    private var key: CalendarKey? = nil
    private var value: CalendarSpan? = nil
    private var months: [Int: CalendarMonth] = [:]
    private var spokenDates: [Date: String] = [:]

    /// Dates follow the group's day clock; only the week's first day comes from the device.
    func span(group: GroupInfo, summary: GroupSummary, standing: MemberStanding, device: Calendar,
              now: Date) -> CalendarSpan? {
        let fresh: CalendarKey = CalendarKey(group: group, summary: summary, standing: standing,
                                             firstWeekday: device.firstWeekday,
                                             clockDay: DayClock.currentDay(group, now: now))
        if let current: CalendarKey = key, current == fresh {
            return value
        }
        if key?.group.timeZoneID != group.timeZoneID {
            spokenDates = [:]
        }
        key = fresh
        value = CalendarSpan(group: group, summary: summary, standing: standing, calendar: device, now: now)
        months = [:]
        weekdays = CalendarMemo.weekdaySymbols(device)
        return value
    }

    /// Month `index` of the current span.
    func month(at index: Int) -> CalendarMonth? {
        if let cached: CalendarMonth = months[index] {
            return cached
        }
        guard let built: CalendarMonth = value?.month(at: index) else { return nil }
        months[index] = built
        return built
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

    /// The symbols start on Sunday; rotate them by firstWeekday − 1 (Monday-first: "M T W T F S S").
    private static func weekdaySymbols(_ device: Calendar) -> [String] {
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
