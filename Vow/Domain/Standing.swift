import Foundation

enum DayOutcome: String, Codable {
    case kept, missed
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
    /// Consecutive kept closed days ending yesterday, +1 if checked in today.
    let streak: Int
    let bestStreak: Int
    /// Closed days since joining (current epoch), oldest first.
    let history: [DayOutcome]
    let checkedInToday: Bool
    let missedYesterday: Bool

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
        case kept, missed, forfeit, payout, split, carry, joined, info
    }

    /// Stable, e.g. "d12-forfeit-<userID>".
    let id: String
    let day: Int
    let kind: Kind
    /// e.g. "Day 13 · Maya missed · −2 pts".
    let text: String
    /// Signed, from the viewer's perspective; only on the viewer's own lines.
    let amount: Double?
}

struct GroupSummary: Equatable {
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
}
