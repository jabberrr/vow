import Foundation

/// Calendar-day arithmetic in a group's time zone. Day 0 is the calendar day the group was created.
enum DayClock {
    /// A check-in that lands at most this long into the next day still counts for its day.
    static let graceSeconds: TimeInterval = 600

    /// Gregorian calendar in the given time zone (falls back to the current time zone).
    static func calendar(_ timeZoneID: String) -> Calendar {
        var cal: Calendar = Calendar(identifier: .gregorian)
        if let tz: TimeZone = TimeZone(identifier: timeZoneID) {
            cal.timeZone = tz
        } else {
            cal.timeZone = TimeZone.current
        }
        return cal
    }

    /// Whole calendar days between the start of `start`'s day and the start of `date`'s day in the
    /// time zone. DST-safe (counts calendar days, not 24-hour blocks). Never negative.
    static func dayIndex(of date: Date, start: Date, timeZoneID: String) -> Int {
        let cal: Calendar = calendar(timeZoneID)
        let from: Date = cal.startOfDay(for: start)
        let to: Date = cal.startOfDay(for: date)
        let days: Int = cal.dateComponents([.day], from: from, to: to).day ?? 0
        return max(0, days)
    }

    /// Test groups use the manually advanced `testDay`; real groups follow the clock.
    static func currentDay(_ group: GroupInfo, now: Date) -> Int {
        if group.isTest {
            return max(0, group.testDay)
        }
        return dayIndex(of: now, start: group.createdAt, timeZoneID: group.timeZoneID)
    }

    /// Start of the next calendar day after `now` in the group's time zone; nil for test groups.
    static func nextDayStart(_ group: GroupInfo, now: Date) -> Date? {
        if group.isTest {
            return nil
        }
        let cal: Calendar = calendar(group.timeZoneID)
        let today: Date = cal.startOfDay(for: now)
        return cal.date(byAdding: .day, value: 1, to: today)
    }

    /// Start of group day `day` (day 0 = creation day) in the group's time zone.
    static func start(ofDay day: Int, group: GroupInfo) -> Date? {
        let cal: Calendar = calendar(group.timeZoneID)
        let first: Date = cal.startOfDay(for: group.createdAt)
        guard let shifted: Date = cal.date(byAdding: .day, value: day, to: first) else { return nil }
        return cal.startOfDay(for: shifted)
    }
}
