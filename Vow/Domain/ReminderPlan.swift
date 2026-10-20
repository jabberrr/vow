import Foundation

/// A real (non-test) group in which you are an active member with a vow.
struct ReminderGroup: Equatable {
    let id: GroupID
    let name: String
    let keptToday: Bool
    /// MemberStanding.streak (today's check-in included once kept).
    let streak: Int
    /// When the vow's final day ends (`EndDate.endsAt`); nil = it never ends. No reminder fires after it.
    var endsAt: Date? = nil
}

/// A silent request at the start of a day that only sets the app badge to 0.
struct ReminderBadgeReset: Equatable {
    let id: String
    let fireDate: Date
}

struct ReminderRequest: Equatable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
    let badge: Int
    /// Deep link when exactly one vow is open.
    let groupID: GroupID?
}

/// Pure planning of the daily reminder: one per calendar day at the chosen time, for the next
/// `days` days, only while a vow is open. Today's is skipped once every vow is kept.
enum ReminderPlan {
    static let days: Int = 7
    static let idPrefix: String = "vow.reminder."
    static let badgePrefix: String = "vow.badge."
    /// 20:00.
    static let defaultMinute: Int = 1200

    /// "2026-10-13" in `calendar`'s time zone.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c: DateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let y: Int = c.year ?? 0
        let m: Int = c.month ?? 0
        let d: Int = c.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// "vow.reminder.2026-10-13".
    static func identifier(for date: Date, calendar: Calendar) -> String {
        return idPrefix + dayKey(date, calendar: calendar)
    }

    /// The reminder time on the day `dayOffset` days after `now`'s day.
    static func fireDate(dayOffset: Int, minuteOfDay: Int, now: Date, calendar: Calendar) -> Date? {
        let today: Date = calendar.startOfDay(for: now)
        guard let day: Date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { return nil }
        let clamped: Int = min(max(minuteOfDay, 0), 24 * 60 - 1)
        return calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: day)
    }

    static func requests(groups: [ReminderGroup], minuteOfDay: Int, now: Date, calendar: Calendar) -> [ReminderRequest] {
        guard !groups.isEmpty else { return [] }
        var out: [ReminderRequest] = []
        for offset in 0..<days {
            guard let fire: Date = fireDate(dayOffset: offset, minuteOfDay: minuteOfDay, now: now, calendar: calendar) else { continue }
            if fire <= now {
                continue
            }
            var open: [ReminderGroup] = []
            for g in groups where (offset > 0 || !g.keptToday) && fire < (g.endsAt ?? Date.distantFuture) {
                open.append(g)
            }
            if open.isEmpty {
                continue
            }
            out.append(request(open: open, isToday: offset == 0, fire: fire, calendar: calendar))
        }
        return out
    }

    private static func request(open: [ReminderGroup], isToday: Bool, fire: Date, calendar: Calendar) -> ReminderRequest {
        let id: String = identifier(for: fire, calendar: calendar)
        if open.count == 1 {
            let g: ReminderGroup = open[0]
            let body: String
            if isToday && g.streak >= 2 {
                body = "Hold the orb to keep your \(g.streak)-day streak."
            } else {
                body = "Your vow is still open today."
            }
            return ReminderRequest(id: id, fireDate: fire, title: g.name, body: body, badge: 1, groupID: g.id)
        }
        return ReminderRequest(id: id, fireDate: fire, title: "Vow",
                               body: "\(open.count) vows are still open today.",
                               badge: open.count, groupID: nil)
    }

    /// Open vows, but only from today's reminder time on (no badge in the morning).
    static func badgeCount(groups: [ReminderGroup], minuteOfDay: Int, now: Date, calendar: Calendar) -> Int {
        guard let fire: Date = fireDate(dayOffset: 0, minuteOfDay: minuteOfDay, now: now, calendar: calendar) else { return 0 }
        if now < fire {
            return 0
        }
        var n: Int = 0
        for g in groups where !g.keptToday {
            n += 1
        }
        return n
    }

    /// Midnight of each planned day after today: clears last night's badge without a sound or banner.
    static func badgeResets(now: Date, calendar: Calendar) -> [ReminderBadgeReset] {
        let today: Date = calendar.startOfDay(for: now)
        var out: [ReminderBadgeReset] = []
        for offset in 1...days {
            guard let day: Date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            out.append(ReminderBadgeReset(id: badgePrefix + dayKey(day, calendar: calendar), fireDate: day))
        }
        return out
    }

    /// Every reminder and badge-reset identifier this plan could have scheduled around `now`
    /// (yesterday through the last planned day).
    static func identifiersToClear(now: Date, calendar: Calendar) -> [String] {
        let today: Date = calendar.startOfDay(for: now)
        var ids: [String] = []
        for offset in -1...days {
            if let day: Date = calendar.date(byAdding: .day, value: offset, to: today) {
                let key: String = dayKey(day, calendar: calendar)
                ids.append(idPrefix + key)
                ids.append(badgePrefix + key)
            }
        }
        return ids
    }

    /// Changes whenever the plan's inputs change (MainView resyncs only then, or on activation).
    static func signature(_ groups: [ReminderGroup]) -> String {
        var parts: [String] = []
        for g in groups {
            parts.append("\(g.id.zoneName)|\(g.name)|\(g.keptToday)|\(g.streak)")
        }
        return parts.joined(separator: ";")
    }
}
