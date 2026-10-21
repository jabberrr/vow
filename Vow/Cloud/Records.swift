import CloudKit
import Foundation

/// CKRecord <-> domain mapping. Record layout is fixed by the shared contract:
/// - "Group" / "group": name, stake, createdAt, timeZoneID, isTest, testDay, epoch, ownerUserID, endDay (optional: the
///   final day's index; absent = no end), voteRules (optional: [fromDay, rule, …]; absent = "More than half" from day 0)
/// - "Member" / "member-<userID>": userID, displayName, vow, joinedDay, joinedEpoch, leftDay (-1 = active)
/// - "CheckIn" / "checkin-<epoch>-<userID>-<day>": userID, day, epoch (server creationDate = trusted time)
/// - "Excuse" / "excuse-<epoch>-<userID>-<day>": userID, day, epoch, text (server creationDate = trusted time)
/// - "Vote" / "vote-<epoch>-<voterID>-<subjectID>-<day>": voterID, subjectID, day, epoch, counts (0/1), castDay
///   (server modificationDate = trusted time)
/// - "Post" / "post-<UUID>": authorID, text, day, epoch, isProof, mediaKind, aspect, duration (server creationDate =
///   sent time), plus the assets media and thumb, which the zone fetch never downloads
enum Records {
    static let groupType: String = "Group"
    static let memberType: String = "Member"
    static let checkInType: String = "CheckIn"
    static let excuseType: String = "Excuse"
    static let voteType: String = "Vote"
    static let postType: String = "Post"

    static let groupRecordName: String = "group"
    static let zonePrefix: String = "group-"

    /// Every non-asset field of every record type. The zone fetch asks for exactly these, so it never downloads a
    /// post's photo, video or thumbnail. A field missing here reads as its default, so list every new field.
    static let snapshotKeys: [CKRecord.FieldKey] = [
        "name", "stake", "createdAt", "timeZoneID", "isTest", "testDay", "epoch", "ownerUserID", "endDay", "voteRules",
        "userID", "displayName", "vow", "joinedDay", "joinedEpoch", "leftDay",
        "day", "text", "voterID", "subjectID", "counts", "castDay",
        "authorID", "isProof", "mediaKind", "aspect", "duration"
    ]

    /// The longest excuse and post text kept. Longer text (only another client could write it) is cut on read.
    static let excuseTextLimit: Int = 280
    static let postTextLimit: Int = 2_000
    /// A post's width / height is kept within this, so a malformed value can't blow up a layout.
    static let aspectRange: ClosedRange<Double> = 0.1...10

    // MARK: - IDs

    static func zoneID(_ id: GroupID) -> CKRecordZone.ID {
        return CKRecordZone.ID(zoneName: id.zoneName, ownerName: id.ownerName)
    }

    static func groupID(_ zoneID: CKRecordZone.ID) -> GroupID {
        return GroupID(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName)
    }

    static func groupRecordID(_ id: GroupID) -> CKRecord.ID {
        return CKRecord.ID(recordName: groupRecordName, zoneID: zoneID(id))
    }

    static func memberRecordID(userID: String, in id: GroupID) -> CKRecord.ID {
        return CKRecord.ID(recordName: "member-" + userID, zoneID: zoneID(id))
    }

    static func checkInRecordID(_ c: CheckInInfo, in id: GroupID) -> CKRecord.ID {
        let name: String = "checkin-\(c.epoch)-\(c.userID)-\(c.day)"
        return CKRecord.ID(recordName: name, zoneID: zoneID(id))
    }

    static func excuseRecordID(_ e: ExcuseInfo, in id: GroupID) -> CKRecord.ID {
        let name: String = "excuse-\(e.epoch)-\(e.userID)-\(e.day)"
        return CKRecord.ID(recordName: name, zoneID: zoneID(id))
    }

    static func voteRecordID(_ v: VoteInfo, in id: GroupID) -> CKRecord.ID {
        let name: String = "vote-\(v.epoch)-\(v.voterID)-\(v.subjectID)-\(v.day)"
        return CKRecord.ID(recordName: name, zoneID: zoneID(id))
    }

    /// A post's record name is its id ("post-<UUID>"), made on the sending device.
    static func postRecordID(_ postID: String, in id: GroupID) -> CKRecord.ID {
        return CKRecord.ID(recordName: postID, zoneID: zoneID(id))
    }

    static func shareRecordID(in id: GroupID) -> CKRecord.ID {
        return CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID(id))
    }

    // MARK: - Field helpers

    static func int(_ record: CKRecord, _ key: String) -> Int? {
        if let n = record[key] as? NSNumber {
            return n.intValue
        }
        if let v = record[key] as? Int64 {
            return Int(v)
        }
        return nil
    }

    /// Finite values only, so a malformed record can't feed NaN into a layout.
    static func double(_ record: CKRecord, _ key: String) -> Double? {
        guard let n = record[key] as? NSNumber, n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }

    static func string(_ record: CKRecord, _ key: String) -> String? {
        return record[key] as? String
    }

    static func date(_ record: CKRecord, _ key: String) -> Date? {
        return record[key] as? Date
    }

    static func number(_ value: Int) -> CKRecordValue {
        return NSNumber(value: Int64(value)) as CKRecordValue
    }

    private static func clipped(_ text: String, to limit: Int) -> String {
        return String(text.prefix(limit))
    }

    // MARK: - Group

    static func groupInfo(from record: CKRecord, id: GroupID) -> GroupInfo {
        let created: Date = date(record, "createdAt") ?? record.creationDate ?? Date()
        let tz: String = string(record, "timeZoneID") ?? TimeZone.current.identifier
        return GroupInfo(
            id: id,
            name: string(record, "name") ?? "Group",
            stake: int(record, "stake") ?? 1,
            createdAt: created,
            timeZoneID: tz,
            isTest: (int(record, "isTest") ?? 0) != 0,
            testDay: int(record, "testDay") ?? 0,
            epoch: int(record, "epoch") ?? 0,
            ownerUserID: string(record, "ownerUserID") ?? "",
            shareURL: nil,
            endDay: endDay(record),
            voteRules: voteRules(record)
        )
    }

    /// endDay is optional: absent means the vow never ends. Values are clamped to
    /// 0...EndDate.maxEndDay so a malformed record can't break the day math.
    static func endDay(_ record: CKRecord) -> Int? {
        guard let v = int(record, "endDay") else { return nil }
        return min(max(v, 0), EndDate.maxEndDay)
    }

    /// voteRules is a flat Int64 list, [fromDay0, rule0, fromDay1, rule1, …]; absent reads as nil ("More than half"
    /// from day 0). A pair with an unknown rule (from a newer build) and an odd last value are dropped, and days are
    /// clamped to 0 or more.
    static func voteRules(_ record: CKRecord) -> [VoteRuleChange]? {
        guard let values = record["voteRules"] as? [NSNumber] else { return nil }
        var rules: [VoteRuleChange] = []
        for i in stride(from: 0, to: values.count - 1, by: 2) {
            if let rule = VoteRule(rawValue: values[i + 1].intValue) {
                rules.append(VoteRuleChange(fromDay: max(values[i].intValue, 0), rule: rule))
            }
        }
        return rules
    }

    /// Never writes voteRules: only `apply(voteRules:to:)` does, on a freshly fetched record, so a stale GroupInfo
    /// (an older cache or build) can't roll the rule back.
    static func apply(_ group: GroupInfo, to record: CKRecord) {
        record["name"] = group.name as CKRecordValue
        record["stake"] = number(group.stake)
        record["createdAt"] = group.createdAt as CKRecordValue
        record["timeZoneID"] = group.timeZoneID as CKRecordValue
        record["isTest"] = number(group.isTest ? 1 : 0)
        record["testDay"] = number(group.testDay)
        record["epoch"] = number(group.epoch)
        record["ownerUserID"] = group.ownerUserID as CKRecordValue
        // endDay never changes after creation, so a GroupInfo without it (e.g. an older cache) must not
        // erase it; groups without an end never touch the field.
        if let end: Int = group.endDay {
            record["endDay"] = number(end)
        }
    }

    /// Writes the whole rule log. An empty log clears the field, which reads the same as absent.
    static func apply(voteRules rules: [VoteRuleChange], to record: CKRecord) {
        guard !rules.isEmpty else {
            record.setObject(nil, forKey: "voteRules")
            return
        }
        var values: [NSNumber] = []
        for change in rules {
            values.append(NSNumber(value: Int64(change.fromDay)))
            values.append(NSNumber(value: Int64(change.rule.rawValue)))
        }
        record["voteRules"] = values as CKRecordValue
    }

    // MARK: - Member

    static func memberInfo(from record: CKRecord) -> MemberInfo? {
        var uid: String = string(record, "userID") ?? ""
        if uid.isEmpty {
            let name: String = record.recordID.recordName
            if name.hasPrefix("member-") {
                uid = String(name.dropFirst("member-".count))
            }
        }
        if uid.isEmpty { return nil }
        return MemberInfo(
            userID: uid,
            displayName: string(record, "displayName") ?? "",
            vow: string(record, "vow") ?? "",
            joinedDay: int(record, "joinedDay") ?? 0,
            joinedEpoch: int(record, "joinedEpoch") ?? 0,
            leftDay: leftDay(record)
        )
    }

    /// leftDay is always written (-1 = active) so the field exists in the schema from the
    /// first member save; -1 or a missing value means "active".
    static func leftDay(_ record: CKRecord) -> Int? {
        guard let v = int(record, "leftDay"), v >= 0 else { return nil }
        return v
    }

    static func apply(_ member: MemberInfo, to record: CKRecord) {
        record["userID"] = member.userID as CKRecordValue
        record["displayName"] = member.displayName as CKRecordValue
        record["vow"] = member.vow as CKRecordValue
        record["joinedDay"] = number(member.joinedDay)
        record["joinedEpoch"] = number(member.joinedEpoch)
        record["leftDay"] = number(member.leftDay ?? -1)
    }

    // MARK: - CheckIn

    static func checkInInfo(from record: CKRecord) -> CheckInInfo? {
        guard let uid = string(record, "userID"), !uid.isEmpty else { return nil }
        guard let day = int(record, "day") else { return nil }
        return CheckInInfo(
            userID: uid,
            day: day,
            epoch: int(record, "epoch") ?? 0,
            serverDate: record.creationDate ?? Date()
        )
    }

    static func apply(_ checkIn: CheckInInfo, to record: CKRecord) {
        record["userID"] = checkIn.userID as CKRecordValue
        record["day"] = number(checkIn.day)
        record["epoch"] = number(checkIn.epoch)
    }

    // MARK: - Excuse

    /// serverDate is the record's creationDate, which every fetched or saved record has; a local record has none
    /// and reads as pending.
    static func excuseInfo(from record: CKRecord) -> ExcuseInfo? {
        guard let uid = string(record, "userID"), !uid.isEmpty else { return nil }
        guard let day = int(record, "day") else { return nil }
        return ExcuseInfo(
            userID: uid,
            day: day,
            epoch: int(record, "epoch") ?? 0,
            text: clipped(string(record, "text") ?? "", to: excuseTextLimit),
            serverDate: record.creationDate
        )
    }

    static func apply(_ excuse: ExcuseInfo, to record: CKRecord) {
        record["userID"] = excuse.userID as CKRecordValue
        record["day"] = number(excuse.day)
        record["epoch"] = number(excuse.epoch)
        record["text"] = clipped(excuse.text, to: excuseTextLimit) as CKRecordValue
    }

    // MARK: - Vote

    /// serverDate is the record's modificationDate, because a changed vote is judged by when it changed. A vote
    /// without its verdict reads as "Counts", which can never overrule anyone; a missing castDay reads as the day
    /// voted on.
    static func voteInfo(from record: CKRecord) -> VoteInfo? {
        guard let voter = string(record, "voterID"), !voter.isEmpty else { return nil }
        guard let subject = string(record, "subjectID"), !subject.isEmpty else { return nil }
        guard let day = int(record, "day") else { return nil }
        return VoteInfo(
            voterID: voter,
            subjectID: subject,
            day: day,
            epoch: int(record, "epoch") ?? 0,
            counts: (int(record, "counts") ?? 1) != 0,
            castDay: int(record, "castDay") ?? day,
            serverDate: record.modificationDate
        )
    }

    static func apply(_ vote: VoteInfo, to record: CKRecord) {
        record["voterID"] = vote.voterID as CKRecordValue
        record["subjectID"] = vote.subjectID as CKRecordValue
        record["day"] = number(vote.day)
        record["epoch"] = number(vote.epoch)
        record["counts"] = number(vote.counts ? 1 : 0)
        record["castDay"] = number(vote.castDay)
    }

    // MARK: - Post

    /// An unknown media kind (from a newer build) reads as text. Only photos and videos keep an aspect, within
    /// `aspectRange`, and only videos a duration.
    static func postInfo(from record: CKRecord) -> PostInfo? {
        guard let author = string(record, "authorID"), !author.isEmpty else { return nil }
        guard let day = int(record, "day") else { return nil }
        let media: MediaKind = MediaKind(rawValue: int(record, "mediaKind") ?? 0) ?? MediaKind.none
        var aspect: Double? = nil
        if media != MediaKind.none, let a = double(record, "aspect"), a > 0 {
            aspect = min(max(a, aspectRange.lowerBound), aspectRange.upperBound)
        }
        var duration: Double? = nil
        if media == .video, let d = double(record, "duration") {
            duration = max(d, 0)
        }
        return PostInfo(
            id: record.recordID.recordName,
            authorID: author,
            text: clipped(string(record, "text") ?? "", to: postTextLimit),
            day: day,
            epoch: int(record, "epoch") ?? 0,
            isProof: (int(record, "isProof") ?? 0) != 0,
            media: media,
            aspect: aspect,
            duration: duration,
            serverDate: record.creationDate
        )
    }

    /// The fields only; `attach` adds the files when the post is first saved.
    static func apply(_ post: PostInfo, to record: CKRecord) {
        record["authorID"] = post.authorID as CKRecordValue
        record["text"] = clipped(post.text, to: postTextLimit) as CKRecordValue
        record["day"] = number(post.day)
        record["epoch"] = number(post.epoch)
        record["isProof"] = number(post.isProof ? 1 : 0)
        record["mediaKind"] = number(post.media.rawValue)
        if let aspect: Double = post.aspect {
            record["aspect"] = NSNumber(value: aspect) as CKRecordValue
        }
        if let duration: Double = post.duration {
            record["duration"] = NSNumber(value: duration) as CKRecordValue
        }
    }

    static func attach(media: URL?, thumb: URL?, to record: CKRecord) {
        if let url: URL = media {
            record[MediaAssetKey.media.rawValue] = CKAsset(fileURL: url) as CKRecordValue
        }
        if let url: URL = thumb {
            record[MediaAssetKey.thumb.rawValue] = CKAsset(fileURL: url) as CKRecordValue
        }
    }
}
