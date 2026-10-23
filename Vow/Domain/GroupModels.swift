import Foundation

/// Identifies a group: its CloudKit record zone name ("group-<UUID>") and the zone owner's name.
struct GroupID: Hashable, Codable {
    var zoneName: String
    var ownerName: String
}

struct GroupInfo: Codable, Equatable {
    var id: GroupID
    var name: String
    /// Points forfeited per missed day.
    var stake: Int
    var createdAt: Date
    var timeZoneID: String
    var isTest: Bool
    var testDay: Int
    var epoch: Int
    var ownerUserID: String
    var shareURL: URL?
    /// Index of the vow's final day, inclusive, in the group's day clock (day 0 = creation day; test
    /// groups count `testDay`). nil = no end. Optional with a default so the memberwise init and old
    /// caches (no "endDay" key) keep working.
    var endDay: Int? = nil
    /// Every change of the vote rule, oldest first; `Review.rule(forDay:group:)` reads it. nil = "More
    /// than half" from day 0. Last, Optional and defaulted for the same reasons as `endDay`.
    var voteRules: [VoteRuleChange]? = nil
}

struct MemberInfo: Codable, Equatable, Identifiable {
    var userID: String
    var displayName: String
    var vow: String
    var joinedDay: Int
    var joinedEpoch: Int
    /// First day NOT participating; nil = active.
    var leftDay: Int?

    var id: String { userID }
}

struct CheckInInfo: Codable, Equatable, Hashable {
    var userID: String
    var day: Int
    var epoch: Int
    /// The record's server creationDate; nil = optimistic/pending (counts as valid).
    var serverDate: Date?
}

/// "Sick, so no gym today": a day you sit out unless the group overrules it. It closes that day's orb
/// for good, and it is valid on exactly a check-in's terms (`Settlement.isValid`).
struct ExcuseInfo: Codable, Equatable, Hashable {
    var userID: String
    var day: Int
    var epoch: Int
    var text: String
    /// The record's server creationDate; nil = optimistic/pending.
    var serverDate: Date?
}

/// One member's say on another's check-in or excuse for a day. One per (voter, subject, day): voting
/// again overwrites it.
struct VoteInfo: Codable, Equatable, Hashable {
    var voterID: String
    var subjectID: String
    var day: Int
    var epoch: Int
    /// "Counts" (true) or "Doesn't count" (false).
    var counts: Bool
    /// The group day on the voter's device when cast. Test groups judge the window by it, because
    /// their days move by hand rather than with the server's clock.
    var castDay: Int
    /// The record's server modificationDate (a changed vote is judged by when it changed); nil = pending.
    var serverDate: Date?
}

enum MediaKind: Int, Codable {
    case none = 0, photo = 1, video = 2
}

/// A chat message: text, or proof with a photo or video.
struct PostInfo: Codable, Equatable, Identifiable {
    /// The record name, "post-<UUID>", created on the device (so an optimistic post and its saved
    /// copy share one id).
    var id: String
    var authorID: String
    var text: String
    /// The group day on the author's device when sent.
    var day: Int
    var epoch: Int
    /// Sent through the proof flow for (authorID, day).
    var isProof: Bool
    var media: MediaKind
    /// Width / height of the photo or video; nil for text.
    var aspect: Double?
    /// Video length in seconds.
    var duration: Double?
    /// The record's server creationDate; nil = pending or still uploading.
    var serverDate: Date?
}

/// One member's reaction to a chat post. One per (user, post): reacting again replaces it, and "" takes it
/// back, because the record is overwritten, never deleted.
struct ReactionInfo: Codable, Equatable, Hashable {
    var userID: String
    var postID: String
    /// One of `Reactions.choices`; any other non-empty string still counts, so a later build's emoji shows.
    /// "" = taken back.
    var emoji: String
    /// The record's server modificationDate (a changed reaction is dated by when it changed); nil = pending.
    var serverDate: Date?
}

/// How many of the eligible voters it takes to overrule a check-in or an excuse.
enum VoteRule: Hashable, Codable {
    case majority
    /// No longer offered. Kept so rule logs and caches written before Custom still read.
    case twoThirds
    case everyone
    /// Custom: this many "Doesn't count" votes, or every voter when fewer take part that day.
    case count(Int)

    /// What the owner can type for Custom.
    static let customRange: ClosedRange<Int> = 1...99

    /// "Doesn't count" votes that overrule a claim with `n` eligible voters (n ≥ 1): more than half,
    /// ⌈2n/3⌉, all of them, or k but never more than there are voters (k kept within `customRange`).
    /// With 3 voters: 2, 2, 3; "2 votes" takes 2 and "5 votes" all 3.
    func needed(voters n: Int) -> Int {
        switch self {
        case .majority: return n / 2 + 1
        case .twoThirds: return (2 * n + 2) / 3
        case .everyone: return n
        case .count(let k): return min(VoteRule.clamped(k), n)
        }
    }

    /// What CloudKit and the cache store: 1, 2 and 3 as before Custom, and 100 + k for "k votes", which
    /// leaves 4...100 for any fixed rule a later build adds. A count outside `customRange` stores as the count
    /// it judges by.
    var code: Int {
        switch self {
        case .majority: return 1
        case .twoThirds: return 2
        case .everyone: return 3
        case .count(let k): return 100 + VoteRule.clamped(k)
        }
    }

    /// nil for a code this build doesn't know (a newer build's rule), or a count outside `customRange`.
    init?(code: Int) {
        switch code {
        case 1: self = .majority
        case 2: self = .twoThirds
        case 3: self = .everyone
        default:
            // Checked above 100 first, so a corrupt code can't overflow the subtraction.
            guard code > 100 && VoteRule.customRange.contains(code - 100) else { return nil }
            self = .count(code - 100)
        }
    }

    /// One Int, `code`: a cache written before Custom holds 1, 2 or 3 there, so it keeps reading.
    init(from decoder: Decoder) throws {
        let container: SingleValueDecodingContainer = try decoder.singleValueContainer()
        let code: Int = try container.decode(Int.self)
        guard let rule: VoteRule = VoteRule(code: code) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown vote rule \(code)")
        }
        self = rule
    }

    func encode(to encoder: Encoder) throws {
        var container: SingleValueEncodingContainer = encoder.singleValueContainer()
        try container.encode(code)
    }

    private static func clamped(_ k: Int) -> Int {
        return min(max(k, customRange.lowerBound), customRange.upperBound)
    }
}

/// From group day `fromDay` on (test groups count `testDay`), claims are judged by `rule`.
struct VoteRuleChange: Codable, Equatable {
    var fromDay: Int
    var rule: VoteRule
}

struct GroupSnapshot: Codable, Equatable, Identifiable {
    var group: GroupInfo
    var members: [MemberInfo]
    var checkIns: [CheckInInfo]
    var fetchedAt: Date
    /// After `fetchedAt` with defaults, so the memberwise init keeps its old shape.
    var excuses: [ExcuseInfo] = []
    var votes: [VoteInfo] = []
    var posts: [PostInfo] = []
    var reactions: [ReactionInfo] = []

    var id: GroupID { group.id }
}

extension GroupSnapshot {
    /// Synthesized decoding would demand the newer keys, and a cache that fails to decode is discarded
    /// whole (it has no schema version): a snapshot cached before chat or reactions reads them as empty. In an
    /// extension, so the memberwise init survives.
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        group = try container.decode(GroupInfo.self, forKey: .group)
        members = try container.decode([MemberInfo].self, forKey: .members)
        checkIns = try container.decode([CheckInInfo].self, forKey: .checkIns)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        excuses = try container.decodeIfPresent([ExcuseInfo].self, forKey: .excuses) ?? []
        votes = try container.decodeIfPresent([VoteInfo].self, forKey: .votes) ?? []
        posts = try container.decodeIfPresent([PostInfo].self, forKey: .posts) ?? []
        reactions = try container.decodeIfPresent([ReactionInfo].self, forKey: .reactions) ?? []
    }
}
