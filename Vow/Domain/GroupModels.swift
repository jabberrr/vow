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

struct GroupSnapshot: Codable, Equatable, Identifiable {
    var group: GroupInfo
    var members: [MemberInfo]
    var checkIns: [CheckInInfo]
    var fetchedAt: Date

    var id: GroupID { group.id }
}
