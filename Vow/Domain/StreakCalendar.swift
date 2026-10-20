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
    /// A vow day still to come (up to the final day; without an end, to the end of the last month).
    case upcoming
    /// Not one of your vow days: before you joined, after the final day, or another date of the month.
    case outside
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
    /// The first day of your current streak.
    let isStreakStart: Bool

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

/// Pure month-by-month layout of your vow days (kept, missed, today, upcoming) for the streak calendar.
/// Weekday headers are the UI's job.
enum StreakCalendar {
    /// Safety cap on the number of months built (just over 100 years).
    static let maxMonths: Int = 1_212

    /// Months from the one containing your first vow day through the one containing max(today, final
    /// day), oldest first; once the vow is finished, through the final day's month. Only
    /// `calendar.firstWeekday` is read from `calendar`: dates always follow the group's day clock
    /// (gregorian in the group's time zone, `DayClock.calendar(group.timeZoneID)`).
    static func months(group: GroupInfo, summary: GroupSummary, standing: MemberStanding, calendar: Calendar) -> [CalendarMonth] {
        var cal: Calendar = DayClock.calendar(group.timeZoneID)
        cal.firstWeekday = calendar.firstWeekday

        let origin: Date = cal.startOfDay(for: group.createdAt)
        let today: Int = summary.currentDay
        let end: Int? = group.endDay
        // standing.history[i] is group day firstDay + i (your participating closed days, contiguous).
        let firstDay: Int = today - standing.history.count
        let context: Context = Context(today: today,
                                       isFinished: summary.isFinished,
                                       endDay: end,
                                       firstDay: firstDay,
                                       history: standing.history,
                                       checkedInToday: standing.checkedInToday,
                                       streakStart: streakStartDay(summary: summary, standing: standing))

        var lastDay: Int = today
        if let finalDay: Int = end {
            lastDay = summary.isFinished ? finalDay : max(today, finalDay)
        }
        lastDay = max(0, lastDay)
        let firstShown: Int = min(max(0, firstDay), lastDay)

        guard let firstDate: Date = date(ofDay: firstShown, origin: origin, calendar: cal),
              let lastDate: Date = date(ofDay: lastDay, origin: origin, calendar: cal),
              let firstMonth: Date = cal.dateInterval(of: .month, for: firstDate)?.start,
              let lastMonth: Date = cal.dateInterval(of: .month, for: lastDate)?.start else { return [] }

        var out: [CalendarMonth] = []
        var offset: Int = 0
        while offset < maxMonths {
            guard let shifted: Date = cal.date(byAdding: .month, value: offset, to: firstMonth),
                  let monthStart: Date = cal.dateInterval(of: .month, for: shifted)?.start else { break }
            if monthStart > lastMonth {
                break
            }
            out.append(month(starting: monthStart, origin: origin, calendar: cal, context: context))
            offset += 1
        }
        return out
    }

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

    // MARK: - Helpers

    /// What decides a group day's state.
    private struct Context {
        let today: Int
        let isFinished: Bool
        let endDay: Int?
        let firstDay: Int
        let history: [DayOutcome]
        let checkedInToday: Bool
        let streakStart: Int?
    }

    private static func month(starting start: Date, origin: Date, calendar cal: Calendar, context: Context) -> CalendarMonth {
        let weekday: Int = cal.component(.weekday, from: start)
        let blanks: Int = ((weekday - cal.firstWeekday) % 7 + 7) % 7
        let count: Int = cal.range(of: .day, in: .month, for: start)?.count ?? 0
        // Group day of the month's first date; the rest follow one calendar day at a time.
        let firstGroupDay: Int = dayOffset(from: origin, to: start, calendar: cal)
        var days: [CalendarDay] = []
        days.reserveCapacity(count)
        for i in 0..<count {
            guard let shifted: Date = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let groupDay: Int = firstGroupDay + i
            days.append(CalendarDay(date: cal.startOfDay(for: shifted),
                                    dayNumber: i + 1,
                                    state: state(ofDay: groupDay, context: context),
                                    isFinal: matches(groupDay, context.endDay),
                                    isStreakStart: matches(groupDay, context.streakStart)))
        }
        return CalendarMonth(start: start, leadingBlanks: blanks, days: days)
    }

    private static func state(ofDay day: Int, context c: Context) -> CalendarDayState {
        if day < 0 || day < c.firstDay {
            return .outside
        }
        if let end: Int = c.endDay, day > end {
            return .outside
        }
        if day < c.today {
            let index: Int = day - c.firstDay
            guard index >= 0 && index < c.history.count else { return .outside }
            return c.history[index] == .kept ? .kept : .missed
        }
        // A finished vow has no today and nothing upcoming.
        if c.isFinished {
            return .outside
        }
        if day == c.today {
            return c.checkedInToday ? .todayKept : .todayOpen
        }
        return .upcoming
    }

    private static func matches(_ day: Int, _ target: Int?) -> Bool {
        guard let t: Int = target else { return false }
        return t == day
    }

    /// Start of group day `day`, counted from `origin` (the start of the creation day), like
    /// DayClock.start(ofDay:group:).
    private static func date(ofDay day: Int, origin: Date, calendar cal: Calendar) -> Date? {
        guard let shifted: Date = cal.date(byAdding: .day, value: day, to: origin) else { return nil }
        return cal.startOfDay(for: shifted)
    }

    /// Signed whole calendar days from `from`'s day to `to`'s day. Noon anchors, as in
    /// DayClock.dayIndex, so DST days count as one day; unlike it, never clamped at 0.
    private static func dayOffset(from: Date, to: Date, calendar cal: Calendar) -> Int {
        let a: Date = cal.date(bySettingHour: 12, minute: 0, second: 0, of: from) ?? cal.startOfDay(for: from)
        let b: Date = cal.date(bySettingHour: 12, minute: 0, second: 0, of: to) ?? cal.startOfDay(for: to)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
