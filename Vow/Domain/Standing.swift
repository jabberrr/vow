import Foundation

/// How a closed day went for a member. `.excused` sits out: no stake lost, no share of the pot, and it
/// neither breaks nor extends a streak.
enum DayOutcome: String, Codable {
    case kept, missed, excused
}

enum MemberStatus: String {
    case checkedIn, missed, notYet, yourMove

    var label: String {
        switch self {
        case .checkedIn: return "checked in"
        case .missed: return "missed"
        case .notYet: return "not yet"
        case .yourMove: return "your move"
        }
    }
}

struct MemberStanding: Identifiable, Equatable {
    let userID: String
    let displayName: String
    let vow: String
    let isActive: Bool
    /// Points won − forfeited in this group (current epoch only).
    let net: Double
    /// Kept closed days back to the last miss (excused days in between don't count or break it), +1
    /// once checked in today unless that check-in is overruled.
    let streak: Int
    let bestStreak: Int
    /// Closed days since joining (current epoch), oldest first.
    let history: [DayOutcome]
    /// A valid check-in exists for today, overruled or not: the orb stays sealed either way.
    let checkedInToday: Bool
    /// Yesterday's outcome was a miss (an overruled check-in or excuse included).
    let missedYesterday: Bool
    /// A valid excuse today and no check-in: today's orb is closed for good.
    var excusedToday: Bool = false
    /// Today's claim (the check-in, else the excuse) is overruled by the votes so far.
    var todayOverruled: Bool = false

    var id: String { userID }

    /// Viewer: checked in or "your move". Others: checked in, missed (yesterday) or not yet.
    func status(isViewer: Bool) -> MemberStatus {
        if checkedInToday {
            return .checkedIn
        }
        if isViewer {
            return .yourMove
        }
        if missedYesterday {
            return .missed
        }
        return .notYet
    }
}

struct LedgerLine: Identifiable, Equatable {
    enum Kind: String {
        case kept, missed, forfeit, payout, split, carry, joined, info, excused
    }

    /// Stable, e.g. "d12-forfeit-<userID>".
    let id: String
    let day: Int
    let kind: Kind
    /// e.g. "Day 13 · Maya missed · −2 pts", "Day 13 · Maya's check-in was overruled · −2 pts".
    let text: String
    /// Signed, from the viewer's perspective; only on the viewer's own lines.
    let amount: Double?
}

struct GroupSummary: Equatable {
    /// Today's day index; once the vow is finished, the day after its final day (endDay + 1).
    let currentDay: Int
    /// currentDay / 30 + 1
    let cycle: Int
    /// currentDay % 30 + 1
    let dayInCycle: Int
    /// currentDay + 1
    let glyphNumber: Int
    /// Unsplit carry after the last closed day.
    let pot: Double
    /// All forfeits in the current epoch.
    let totalForfeited: Double
    /// Active members; viewer first, then by displayName.
    let standings: [MemberStanding]
    /// Newest first, capped at 120.
    let ledger: [LedgerLine]
    let viewer: MemberStanding?
    /// GroupInfo.endDay: the vow's final day (inclusive); nil = no end.
    var endDay: Int? = nil
    /// The final day has passed: nothing is open and nothing settles any more.
    var isFinished: Bool = false
}
