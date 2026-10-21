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

    /// The day's orb colours without another Settlement pass (AppStore.theme(for:) does one).
    static func theme(_ summary: GroupSummary) -> DailyTheme {
        return DailyTheme.make(cycle: summary.cycle, day: summary.dayInCycle)
    }
}

/// Today's state of one of your vows, as the sidebar rows show it.
enum VowStatus: Equatable {
    /// Your turn.
    case open
    /// Your turn, in the last 4 h of a real group's day (`DayWindow.atRiskSeconds`).
    case atRisk
    case kept
    /// You sent an excuse today and it stands: the day sits out.
    case excused
    /// Your check-in or excuse today is overruled by the votes so far.
    case overruled
    /// You are not a member yet (joined by link without a vow).
    case notJoined
    /// The final day has passed.
    case finished
}

/// Your other vows still open today, in store order: the ≡ pulse after a keep, its VoiceOver value, and
/// (when `atRisk`) its flame dot.
struct MenuDot: Equatable {
    let names: [String]
    let atRisk: Bool

    /// VoiceOver value of ≡: "Read Nightly is still open" / "2 other vows are still open".
    var spoken: String {
        if names.count == 1, let name: String = names.first {
            return name + " is still open"
        }
        return "\(names.count) other vows are still open"
    }
}

extension Overview {
    /// `holdingLight`: you have just sealed this vow on Home and its light waits for the social beat.
    static func status(_ summary: GroupSummary, group: GroupInfo, now: Date, holdingLight: Bool) -> VowStatus {
        if summary.isFinished {
            return .finished
        }
        guard let viewer: MemberStanding = summary.viewer else { return .notJoined }
        if viewer.checkedInToday && !holdingLight {
            return viewer.todayOverruled ? .overruled : .kept
        }
        if viewer.excusedToday {
            return viewer.todayOverruled ? .overruled : .excused
        }
        return DayWindow.isAtRisk(group, now: now) ? .atRisk : .open
    }

    /// nil when none of your vows other than `selected` is still open today.
    static func menuDot(_ all: [GroupID: GroupSummary], groups: [GroupInfo], selected: GroupID?, now: Date) -> MenuDot? {
        var names: [String] = []
        var atRisk: Bool = false
        for group in groups where group.id != selected {
            guard let summary: GroupSummary = all[group.id] else { continue }
            let state: VowStatus = status(summary, group: group, now: now, holdingLight: false)
            if state == .open || state == .atRisk {
                names.append(group.name)
            }
            if state == .atRisk {
                atRisk = true
            }
        }
        if names.isEmpty {
            return nil
        }
        return MenuDot(names: names, atRisk: atRisk)
    }

    /// The orb colours of group day `day` (a calendar cell, the finished vow's final day).
    static func theme(day: Int) -> DailyTheme {
        let d: Int = max(0, day)
        return DailyTheme.make(cycle: d / 30 + 1, day: d % 30 + 1)
    }
}
