import Foundation

enum Digest {
    /// What `day` did to the viewer's net: the share if they kept it, minus the stake if they forfeited it.
    /// 0 when they sat it out, it is still open, or it isn't listed.
    static func viewerChange(_ days: [LedgerDay], day: Int, viewerID: String) -> Double {
        var total: Double = 0
        for entry in days where entry.day == day {
            for p in entry.kept where p.userID == viewerID {
                total += entry.share
            }
            for forfeit in entry.forfeits where forfeit.person.userID == viewerID {
                total -= forfeit.amount
            }
        }
        return total
    }

    /// You are an active member, the vow isn't finished, and you have neither checked in nor sent an
    /// excuse today (either closes the orb, whatever the votes say).
    static func isOpen(_ summary: GroupSummary) -> Bool {
        if summary.isFinished {
            return false
        }
        guard let viewer: MemberStanding = summary.viewer else { return false }
        return !viewer.checkedInToday && !viewer.excusedToday
    }

    /// Closed days kept in the current epoch, plus today once a check-in stands.
    static func daysKept(_ standing: MemberStanding) -> Int {
        var n: Int = checkInStands(standing) ? 1 : 0
        for outcome in standing.history where outcome == .kept {
            n += 1
        }
        return n
    }

    /// Checked in today, and the votes so far haven't overruled it.
    static func checkInStands(_ standing: MemberStanding) -> Bool {
        return standing.checkedInToday && !standing.todayOverruled
    }

    /// Sent an excuse today, and the votes so far haven't overruled it: the day sits out.
    static func excuseStands(_ standing: MemberStanding) -> Bool {
        return standing.excusedToday && !standing.todayOverruled
    }
}

enum DayWindow {
    /// From this many seconds before the day closes, an open vow is "at risk".
    static let atRiskSeconds: TimeInterval = 4 * 60 * 60

    /// Seconds until the group's next day; nil for test groups.
    static func secondsLeft(_ group: GroupInfo, now: Date) -> TimeInterval? {
        guard let next: Date = DayClock.nextDayStart(group, now: now) else { return nil }
        return max(0, next.timeIntervalSince(now))
    }

    static func isAtRisk(_ group: GroupInfo, now: Date) -> Bool {
        guard let left: TimeInterval = secondsLeft(group, now: now) else { return false }
        return left < atRiskSeconds
    }

    /// "5h 12m", "5h", "18m"; nil under a minute.
    static func span(_ seconds: TimeInterval) -> String? {
        let total: Int = max(0, Int(seconds))
        let hours: Int = total / 3600
        let minutes: Int = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return nil
    }
}
