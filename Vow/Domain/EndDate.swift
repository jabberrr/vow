import Foundation

/// A group's optional end date. `GroupInfo.endDay` is the index of the vow's final day, inclusive, in
/// the group's day clock (day 0 = creation day; test groups count `testDay`); nil = the vow never ends.
/// After the final day the vow is finished: nothing is open, nothing settles, nothing is reminded.
enum EndDate {
    /// The largest stored endDay (about 100 years), so day math on a malformed record can't overflow.
    static let maxEndDay: Int = 36_500

    /// True once the group's final day has passed (clock day > endDay).
    static func isFinished(_ group: GroupInfo, now: Date) -> Bool {
        guard let end: Int = group.endDay else { return false }
        return DayClock.currentDay(group, now: now) > end
    }

    /// "Day x of y" numbers while an end date is set and the vow is not finished; nil otherwise.
    /// (currentDay + 1, endDay + 1).
    static func dayCounter(_ summary: GroupSummary) -> (day: Int, total: Int)? {
        guard let end: Int = summary.endDay, !summary.isFinished else { return nil }
        return (day: summary.currentDay + 1, total: end + 1)
    }

    /// Start of the final day in the group's time zone (nil without an end).
    static func finalDate(_ group: GroupInfo) -> Date? {
        guard let end: Int = group.endDay else { return nil }
        return DayClock.start(ofDay: end, group: group)
    }

    /// The moment the final day ends: the start of the day after it (nil without an end).
    static func endsAt(_ group: GroupInfo) -> Date? {
        guard let end: Int = group.endDay else { return nil }
        return DayClock.start(ofDay: end + 1, group: group)
    }
}
