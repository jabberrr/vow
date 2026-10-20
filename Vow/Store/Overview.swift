import SwiftUI

/// Pure aggregates over ONE Settlement pass (`AppStore.summaries()`): compute the map once per body
/// and pass it here. Numbers that claim to be about real days (yesterday, days kept, best streak)
/// skip test groups, whose days are moved by hand. The total balance keeps them, as the store's
/// `totalBalance` always has.
enum Overview {
    static func balance(_ all: [GroupID: GroupSummary]) -> Double {
        var total: Double = 0
        for (_, summary) in all {
            if let viewer: MemberStanding = summary.viewer {
                total += viewer.net
            }
        }
        return total
    }

    /// Sum of your signed ledger amounts on each real group's previous day. A finished vow has no
    /// yesterday (its `currentDay` stays at the day after the final one).
    static func yesterdayChange(_ all: [GroupID: GroupSummary], tests: Set<GroupID>) -> Double {
        var total: Double = 0
        for (id, summary) in all where !tests.contains(id) && !summary.isFinished {
            total += Digest.viewerChange(summary.ledger, day: summary.currentDay - 1)
        }
        return total
    }

    /// Kept days across your current real groups (current epoch), today included once kept.
    static func daysKept(_ all: [GroupID: GroupSummary], tests: Set<GroupID>) -> Int {
        var total: Int = 0
        for (id, summary) in all where !tests.contains(id) {
            if let viewer: MemberStanding = summary.viewer {
                total += Digest.daysKept(viewer)
            }
        }
        return total
    }

    static func bestStreak(_ all: [GroupID: GroupSummary], tests: Set<GroupID>) -> Int {
        var best: Int = 0
        for (id, summary) in all where !tests.contains(id) {
            if let viewer: MemberStanding = summary.viewer {
                best = max(best, viewer.bestStreak)
            }
        }
        return best
    }

    /// Groups in which you are an active member.
    static func vowCount(_ all: [GroupID: GroupSummary]) -> Int {
        var n: Int = 0
        for (_, summary) in all where summary.viewer != nil {
            n += 1
        }
        return n
    }

    static func keptTodayCount(_ all: [GroupID: GroupSummary]) -> Int {
        var n: Int = 0
        for (_, summary) in all {
            if summary.viewer?.checkedInToday == true {
                n += 1
            }
        }
        return n
    }

    /// The day's orb colours without another Settlement pass (AppStore.theme(for:) does one).
    static func theme(_ summary: GroupSummary) -> DailyTheme {
        return DailyTheme.make(cycle: summary.cycle, day: summary.dayInCycle)
    }
}
