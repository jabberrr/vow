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

/// Someone in a day of the ledger. `name` is their display name as stored: the UI says "You" for the viewer.
struct LedgerPerson: Equatable, Hashable {
    let userID: String
    let name: String
}

/// A stake lost on a closed day: no claim, or a claim the group overruled.
struct Forfeit: Equatable {
    enum Reason: Equatable {
        case missed
        case checkInOverruled
        case excuseOverruled
    }

    let person: LedgerPerson
    let reason: Reason
    /// The group's stake, positive.
    let amount: Double
}

/// One day of the ledger, as the Activity tab shows it. Every list is in Settlement's member order, and the
/// day reads the same on every device and for every viewer. Each keeper collects `forfeit.amount /
/// kept.count` from each forfeit and `carriedIn / kept.count` from the carry, which add up to `share`.
struct LedgerDay: Identifiable, Equatable {
    let day: Int
    /// false only for today, which carries joins and leaves alone: no outcomes and no money until it
    /// closes (the carry it starts with is `GroupSummary.pot`). A finished vow lists nothing after its
    /// final day.
    let isClosed: Bool
    let joined: [LedgerPerson]
    let left: [LedgerPerson]
    /// Standing check-ins: each collects `share`.
    let kept: [LedgerPerson]
    /// Standing excuses: they sit the day out, neither paying nor collecting.
    let excused: [LedgerPerson]
    let forfeits: [Forfeit]
    /// The pot carried in from earlier days that nobody kept.
    let carriedIn: Double
    /// What each keeper collects: (carriedIn + the day's forfeits) / kept.count; 0 when nobody kept.
    let share: Double
    /// Left unsplit for the next day because nobody kept: carriedIn + the day's forfeits (just carriedIn on
    /// a day everyone sat out); 0 when someone kept.
    let carriedOut: Double

    var id: Int { day }
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
    /// Newest first, capped at `Settlement.dayCap` days: every closed day anyone took part in, joined or
    /// left on, and today once someone joins or leaves.
    let days: [LedgerDay]
    let viewer: MemberStanding?
    /// GroupInfo.endDay: the vow's final day (inclusive); nil = no end.
    var endDay: Int? = nil
    /// The final day has passed: nothing is open and nothing settles any more.
    var isFinished: Bool = false
}
