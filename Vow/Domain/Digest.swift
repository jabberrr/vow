import Foundation

enum Digest {
    /// Sum of the viewer's own signed amounts on `day` (missed = -stake, payout = +share).
    static func viewerChange(_ ledger: [LedgerLine], day: Int) -> Double {
        var total: Double = 0
        for line in ledger where line.day == day {
            if let amount: Double = line.amount {
                total += amount
            }
        }
        return total
    }

    /// You are an active member, the vow isn't finished, and you haven't checked in today.
    static func isOpen(_ summary: GroupSummary) -> Bool {
        if summary.isFinished {
            return false
        }
        guard let viewer: MemberStanding = summary.viewer else { return false }
        return !viewer.checkedInToday
    }

    static func keptCount(_ standings: [MemberStanding]) -> Int {
        var n: Int = 0
        for s in standings where s.checkedInToday {
            n += 1
        }
        return n
    }

    /// Closed days kept in the current epoch, plus today once checked in.
    static func daysKept(_ standing: MemberStanding) -> Int {
        var n: Int = standing.checkedInToday ? 1 : 0
        for outcome in standing.history where outcome == .kept {
            n += 1
        }
        return n
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
