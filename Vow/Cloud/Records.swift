import CloudKit
import Foundation

/// CKRecord <-> domain mapping. Record layout is fixed by the shared contract:
/// - "Group"   / "group"                               : name, stake, createdAt, timeZoneID, isTest, testDay, epoch, ownerUserID
/// - "Member"  / "member-<userID>"                     : userID, displayName, vow, joinedDay, joinedEpoch, leftDay (-1 = active)
/// - "CheckIn" / "checkin-<epoch>-<userID>-<day>"      : userID, day, epoch (server creationDate = trusted time)
enum Records {
    static let groupType: String = "Group"
    static let memberType: String = "Member"
    static let checkInType: String = "CheckIn"

    static let groupRecordName: String = "group"
    static let zonePrefix: String = "group-"

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

    static func string(_ record: CKRecord, _ key: String) -> String? {
        return record[key] as? String
    }

    static func date(_ record: CKRecord, _ key: String) -> Date? {
        return record[key] as? Date
    }

    static func number(_ value: Int) -> CKRecordValue {
        return NSNumber(value: Int64(value)) as CKRecordValue
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
            shareURL: nil
        )
    }

    static func apply(_ group: GroupInfo, to record: CKRecord) {
        record["name"] = group.name as CKRecordValue
        record["stake"] = number(group.stake)
        record["createdAt"] = group.createdAt as CKRecordValue
        record["timeZoneID"] = group.timeZoneID as CKRecordValue
        record["isTest"] = number(group.isTest ? 1 : 0)
        record["testDay"] = number(group.testDay)
        record["epoch"] = number(group.epoch)
        record["ownerUserID"] = group.ownerUserID as CKRecordValue
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
}
