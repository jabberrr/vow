import Foundation

/// How one date of the streak calendar reads for you.
enum CalendarDayState: Equatable {
    /// A closed vow day you kept.
    case kept
    /// A closed vow day you missed.
    case missed
    /// Today, not kept yet.
    case todayOpen
    /// Today, kept.
    case todayKept
    /// A vow day still to come: up to the final day, or for good without an end.
    case upcoming
    /// Not one of your vow days: before the group began or you joined, or after the final day.
    case outside

    /// Kept, today included: these days share the streak's highlight.
    var isKept: Bool {
        self == .kept || self == .todayKept
    }
}

/// One date of a month in the streak calendar.
struct CalendarDay: Equatable, Identifiable {
    /// Start of that calendar day in the group's time zone.
    let date: Date
    /// 1...31 within the month.
    let dayNumber: Int
    let state: CalendarDayState
    /// The vow's final day (the end date's flag).
    let isFinal: Bool
    /// Kept, and so is the date before it in the same week row: one highlight runs through both.
    /// Never across a row's or a month's edge, so each row's part of a run is one whole capsule.
    let joinsPrevious: Bool
    /// Kept, and so is the date after it in the same week row.
    let joinsNext: Bool
    /// The group day index of this date (negative before the group began).
    let groupDay: Int

    var id: Date { date }
}

/// One month of the streak calendar.
struct CalendarMonth: Equatable, Identifiable {
    /// Start of the month's first day in the group's time zone.
    let start: Date
    /// Empty cells before day 1 in a week row that begins on the calendar's firstWeekday.
    let leadingBlanks: Int
    /// Every date of the month, in order.
    let days: [CalendarDay]

    var id: Date { start }
}

/// The months the streak calendar can page through, oldest first: from the month the group began (group
/// day 0) through max(the current month + `StreakCalendar.monthsAhead`, the final day's month). A month
/// is laid out only when asked for, so a long-running group never builds years of dates up front.
/// Weekday headers are the UI's job.
struct CalendarSpan {
    /// Months in the span: at least 1, at most `StreakCalendar.maxMonths`.
    let count: Int
    /// The month the calendar opens on: today's; once the vow is finished, the final day's.
    let home: Int

    /// The group's day clock (gregorian in its time zone) with the device's first weekday.
    private let calendar: Calendar
    /// Start of group day 0.
    private let origin: Date
    /// Start of month 0, the one holding group day 0.
    private let firstMonth: Date
    private let today: Int
    private let endDay: Int?
    /// Your first vow day: `history[i]` is group day `firstDay + i` (your closed days, contiguous).
    private let firstDay: Int
    private let history: [DayOutcome]
    private let checkedInToday: Bool

    /// Only `calendar.firstWeekday` is read from `calendar`: dates always follow the group's day clock
    /// (`DayClock.calendar(group.timeZoneID)`). `now` places the current month, because a finished
    /// summary stops at the day after the final day while the clock (a test group's `testDay`) goes on.
    /// nil only if the calendar can't do the date arithmetic.
    init?(group: GroupInfo, summary: GroupSummary, standing: MemberStanding, calendar device: Calendar, now: Date) {
        var cal: Calendar = DayClock.calendar(group.timeZoneID)
        cal.firstWeekday = device.firstWeekday
        let origin: Date = cal.startOfDay(for: group.createdAt)
        let today: Int = summary.currentDay
        let clockDay: Int = max(today, DayClock.currentDay(group, now: now))
        let homeDay: Int = summary.isFinished ? (group.endDay ?? today) : today

        guard let firstMonth: Date = cal.dateInterval(of: .month, for: origin)?.start,
              let clockMonth: Int = CalendarSpan.monthIndex(ofDay: clockDay, origin: origin, calendar: cal),
              let homeMonth: Int = CalendarSpan.monthIndex(ofDay: homeDay, origin: origin, calendar: cal) else { return nil }
        var last: Int = clockMonth + StreakCalendar.monthsAhead
        if let end: Int = group.endDay,
           let endMonth: Int = CalendarSpan.monthIndex(ofDay: end, origin: origin, calendar: cal) {
            last = max(last, endMonth)
        }
        let count: Int = min(last + 1, StreakCalendar.maxMonths)

        self.count = count
        self.home = min(homeMonth, count - 1)
        self.calendar = cal
        self.origin = origin
        self.firstMonth = firstMonth
        self.today = today
        self.endDay = group.endDay
        self.firstDay = today - standing.history.count
        self.history = standing.history
        self.checkedInToday = standing.checkedInToday
    }

    /// Month `index` (0 = the month the group began); nil outside 0..<count.
    func month(at index: Int) -> CalendarMonth? {
        guard index >= 0 && index < count,
              let shifted: Date = calendar.date(byAdding: .month, value: index, to: firstMonth),
              let start: Date = calendar.dateInterval(of: .month, for: shifted)?.start else { return nil }
        let weekday: Int = calendar.component(.weekday, from: start)
        let blanks: Int = ((weekday - calendar.firstWeekday) % 7 + 7) % 7
        let length: Int = calendar.range(of: .day, in: .month, for: start)?.count ?? 0
        // Group day of the month's first date; the rest follow one calendar day at a time.
        let firstGroupDay: Int = CalendarSpan.dayOffset(from: origin, to: start, calendar: calendar)
        var states: [CalendarDayState] = []
        states.reserveCapacity(length)
        for i in 0..<length {
            states.append(state(ofDay: firstGroupDay + i))
        }
        var days: [CalendarDay] = []
        days.reserveCapacity(length)
        for i in 0..<length {
            guard let date: Date = calendar.date(byAdding: .day, value: i, to: start) else { continue }
            let column: Int = (blanks + i) % 7
            let kept: Bool = states[i].isKept
            days.append(CalendarDay(date: calendar.startOfDay(for: date),
                                    dayNumber: i + 1,
                                    state: states[i],
                                    isFinal: endDay == firstGroupDay + i,
                                    joinsPrevious: kept && column > 0 && i > 0 && states[i - 1].isKept,
                                    joinsNext: kept && column < 6 && i + 1 < length && states[i + 1].isKept,
                                    groupDay: firstGroupDay + i))
        }
        return CalendarMonth(start: start, leadingBlanks: blanks, days: days)
    }

    // MARK: - Helpers

    private func state(ofDay day: Int) -> CalendarDayState {
        if day < 0 || day < firstDay {
            return .outside
        }
        // Past the final day; a finished vow's today (`endDay + 1`) and everything after it included.
        if let end: Int = endDay, day > end {
            return .outside
        }
        if day < today {
            let index: Int = day - firstDay
            guard index < history.count else { return .outside }
            return history[index] == .kept ? .kept : .missed
        }
        if day == today {
            return checkedInToday ? .todayKept : .todayOpen
        }
        return .upcoming
    }

    /// Months from month 0 to the one holding group day `day`. Counted from year and month numbers, not
    /// a date difference: a month that starts at 01:00 (midnight skipped for DST) is still a whole month.
    private static func monthIndex(ofDay day: Int, origin: Date, calendar cal: Calendar) -> Int? {
        guard let date: Date = cal.date(byAdding: .day, value: day, to: origin) else { return nil }
        let from: DateComponents = cal.dateComponents([.year, .month], from: origin)
        let to: DateComponents = cal.dateComponents([.year, .month], from: date)
        guard let fromYear: Int = from.year, let fromMonth: Int = from.month,
              let toYear: Int = to.year, let toMonth: Int = to.month else { return nil }
        return (toYear - fromYear) * 12 + (toMonth - fromMonth)
    }

    /// Signed whole calendar days from `from`'s day to `to`'s day. Noon anchors, as in
    /// DayClock.dayIndex, so DST days count as one day; unlike it, never clamped at 0.
    private static func dayOffset(from: Date, to: Date, calendar cal: Calendar) -> Int {
        let a: Date = cal.date(bySettingHour: 12, minute: 0, second: 0, of: from) ?? cal.startOfDay(for: from)
        let b: Date = cal.date(bySettingHour: 12, minute: 0, second: 0, of: to) ?? cal.startOfDay(for: to)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

/// The streak calendar's limits, and when the current streak began.
enum StreakCalendar {
    /// Months past the current one that ‹ › can reach.
    static let monthsAhead: Int = 12
    /// Safety cap on a span's months (just over 100 years).
    static let maxMonths: Int = 1_212

    /// Group day index where the current streak began; nil when the streak is 0.
    /// Last kept day = checkedInToday ? currentDay : currentDay - 1; start = last - streak + 1.
    static func streakStartDay(summary: GroupSummary, standing: MemberStanding) -> Int? {
        guard standing.streak > 0 else { return nil }
        let keptToday: Bool = standing.checkedInToday && !summary.isFinished
        let last: Int = keptToday ? summary.currentDay : summary.currentDay - 1
        return max(0, last - standing.streak + 1)
    }

    /// Start of the current streak's first day in the group's time zone; nil when the streak is 0.
    static func streakStartDate(group: GroupInfo, summary: GroupSummary, standing: MemberStanding) -> Date? {
        guard let day: Int = streakStartDay(summary: summary, standing: standing) else { return nil }
        return DayClock.start(ofDay: day, group: group)
    }
}
