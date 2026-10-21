import CloudKit
import XCTest
@testable import Vow

/// Record mapping for the chat types and the vote rule log. Records are built locally and never saved, so no
/// container is touched (and an unsaved record has no creationDate or modificationDate).
final class RecordsTests: XCTestCase {

    // MARK: - Fixtures

    private let id: GroupID = GroupID(zoneName: "group-chat", ownerName: "owner")

    private func record(_ type: String, _ name: String) -> CKRecord {
        return CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: Records.zoneID(id)))
    }

    private func makeGroup(endDay: Int? = 29, voteRules: [VoteRuleChange]? = nil) -> GroupInfo {
        return GroupInfo(id: id,
                         name: "Chat",
                         stake: 2,
                         createdAt: Date(timeIntervalSince1970: 1_767_225_600),
                         timeZoneID: "America/New_York",
                         isTest: false,
                         testDay: 0,
                         epoch: 0,
                         ownerUserID: "me",
                         shareURL: nil,
                         endDay: endDay,
                         voteRules: voteRules)
    }

    private func videoPost() -> PostInfo {
        return PostInfo(id: "post-1F2E", authorID: "maya", text: "Done, 5 km", day: 3, epoch: 1, isProof: true,
                        media: .video, aspect: 0.5625, duration: 12.5, serverDate: nil)
    }

    private func numbers(_ values: [Int]) -> CKRecordValue {
        var out: [NSNumber] = []
        for v in values {
            out.append(NSNumber(value: Int64(v)))
        }
        return out as CKRecordValue
    }

    private func storedNumbers(_ record: CKRecord, _ key: String) -> [Int]? {
        guard let values = record[key] as? [NSNumber] else { return nil }
        var out: [Int] = []
        for v in values {
            out.append(v.intValue)
        }
        return out
    }

    // MARK: - Excuse

    func testExcuseRecordNameAndRoundTrip() {
        let excuse: ExcuseInfo = ExcuseInfo(userID: "maya", day: 4, epoch: 2, text: "Sick, so no gym today", serverDate: nil)
        let recordID: CKRecord.ID = Records.excuseRecordID(excuse, in: id)
        XCTAssertEqual(recordID.recordName, "excuse-2-maya-4")
        XCTAssertEqual(recordID.zoneID.zoneName, "group-chat")

        let r: CKRecord = CKRecord(recordType: Records.excuseType, recordID: recordID)
        Records.apply(excuse, to: r)
        XCTAssertEqual(Records.int(r, "day"), 4)
        XCTAssertEqual(Records.int(r, "epoch"), 2)
        XCTAssertEqual(Records.excuseInfo(from: r), excuse)
    }

    func testExcuseDecodingIsLenient() {
        let r: CKRecord = record(Records.excuseType, "excuse-0-maya-1")
        XCTAssertNil(Records.excuseInfo(from: r))
        r["userID"] = "maya" as CKRecordValue
        XCTAssertNil(Records.excuseInfo(from: r))
        r["day"] = Records.number(1)

        let bare: ExcuseInfo? = Records.excuseInfo(from: r)
        XCTAssertEqual(bare?.epoch, 0)
        XCTAssertEqual(bare?.text, "")
        XCTAssertNil(bare?.serverDate)

        r["text"] = String(repeating: "a", count: 500) as CKRecordValue
        XCTAssertEqual(Records.excuseInfo(from: r)?.text.count, Records.excuseTextLimit)
    }

    // MARK: - Vote

    func testVoteRecordNameAndRoundTrip() {
        let vote: VoteInfo = VoteInfo(voterID: "ari", subjectID: "maya", day: 3, epoch: 1, counts: false, castDay: 4,
                                      serverDate: nil)
        let recordID: CKRecord.ID = Records.voteRecordID(vote, in: id)
        XCTAssertEqual(recordID.recordName, "vote-1-ari-maya-3")

        let r: CKRecord = CKRecord(recordType: Records.voteType, recordID: recordID)
        Records.apply(vote, to: r)
        XCTAssertEqual(Records.int(r, "counts"), 0)
        XCTAssertEqual(Records.voteInfo(from: r), vote)

        var counts: VoteInfo = vote
        counts.counts = true
        Records.apply(counts, to: r)
        XCTAssertEqual(Records.int(r, "counts"), 1)
        XCTAssertEqual(Records.voteInfo(from: r)?.counts, true)
    }

    func testVoteDecodingDefaultsCanNeverOverrule() {
        let r: CKRecord = record(Records.voteType, "vote-0-ari-maya-5")
        r["voterID"] = "ari" as CKRecordValue
        r["day"] = Records.number(5)
        XCTAssertNil(Records.voteInfo(from: r))
        r["subjectID"] = "maya" as CKRecordValue

        let bare: VoteInfo? = Records.voteInfo(from: r)
        XCTAssertEqual(bare?.counts, true)
        XCTAssertEqual(bare?.castDay, 5)
        XCTAssertEqual(bare?.epoch, 0)
        XCTAssertNil(bare?.serverDate)

        r["subjectID"] = "" as CKRecordValue
        XCTAssertNil(Records.voteInfo(from: r))
    }

    // MARK: - Post

    func testPostRoundTripKeepsItsId() {
        let post: PostInfo = videoPost()
        let r: CKRecord = CKRecord(recordType: Records.postType, recordID: Records.postRecordID(post.id, in: id))
        XCTAssertEqual(r.recordID.recordName, "post-1F2E")
        Records.apply(post, to: r)
        XCTAssertEqual(Records.int(r, "isProof"), 1)
        XCTAssertEqual(Records.int(r, "mediaKind"), MediaKind.video.rawValue)
        XCTAssertEqual(Records.postInfo(from: r), post)
        XCTAssertNil(r.object(forKey: MediaAssetKey.media.rawValue))
        XCTAssertNil(r.object(forKey: MediaAssetKey.thumb.rawValue))
    }

    func testTextPostWritesNoShape() {
        let text: PostInfo = PostInfo(id: "post-T", authorID: "me", text: "On my way", day: 0, epoch: 0, isProof: false,
                                      media: .none, aspect: nil, duration: nil, serverDate: nil)
        let r: CKRecord = record(Records.postType, text.id)
        Records.apply(text, to: r)
        XCTAssertFalse(r.changedKeys().contains("aspect"))
        XCTAssertFalse(r.changedKeys().contains("duration"))
        XCTAssertEqual(Records.postInfo(from: r), text)
    }

    func testPostDecodingIsLenient() {
        let r: CKRecord = record(Records.postType, "post-L")
        r["day"] = Records.number(2)
        XCTAssertNil(Records.postInfo(from: r))
        r["authorID"] = "maya" as CKRecordValue

        let bare: PostInfo? = Records.postInfo(from: r)
        XCTAssertEqual(bare?.id, "post-L")
        XCTAssertEqual(bare?.text, "")
        XCTAssertEqual(bare?.media, MediaKind.none)
        XCTAssertEqual(bare?.isProof, false)
        XCTAssertNil(bare?.aspect)
        XCTAssertNil(bare?.serverDate)

        // A kind from a newer build reads as text, and text carries no shape.
        r["mediaKind"] = Records.number(7)
        r["aspect"] = NSNumber(value: 1.5) as CKRecordValue
        XCTAssertEqual(Records.postInfo(from: r)?.media, MediaKind.none)
        XCTAssertNil(Records.postInfo(from: r)?.aspect)

        // A photo keeps its aspect, within range, and never a duration.
        r["mediaKind"] = Records.number(MediaKind.photo.rawValue)
        r["duration"] = NSNumber(value: 9.0) as CKRecordValue
        XCTAssertEqual(Records.postInfo(from: r)?.aspect ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertNil(Records.postInfo(from: r)?.duration)
        r["aspect"] = NSNumber(value: 0.001) as CKRecordValue
        XCTAssertEqual(Records.postInfo(from: r)?.aspect ?? 0, Records.aspectRange.lowerBound, accuracy: 1e-9)
        r["aspect"] = NSNumber(value: 50.0) as CKRecordValue
        XCTAssertEqual(Records.postInfo(from: r)?.aspect ?? 0, Records.aspectRange.upperBound, accuracy: 1e-9)
        r["aspect"] = NSNumber(value: -1.0) as CKRecordValue
        XCTAssertNil(Records.postInfo(from: r)?.aspect)

        // A video keeps its duration, never below 0.
        r["mediaKind"] = Records.number(MediaKind.video.rawValue)
        XCTAssertEqual(Records.postInfo(from: r)?.duration ?? 0, 9, accuracy: 1e-9)
        r["duration"] = NSNumber(value: -3.0) as CKRecordValue
        XCTAssertEqual(Records.postInfo(from: r)?.duration ?? 99, 0, accuracy: 1e-9)

        r["text"] = String(repeating: "b", count: 2_500) as CKRecordValue
        XCTAssertEqual(Records.postInfo(from: r)?.text.count, Records.postTextLimit)
    }

    func testAttachPutsFilesUnderTheAssetKeys() throws {
        let media: URL = FileManager.default.temporaryDirectory.appendingPathComponent("records-test-media.mp4")
        let thumb: URL = FileManager.default.temporaryDirectory.appendingPathComponent("records-test-thumb.jpg")
        try Data([1, 2, 3]).write(to: media)
        try Data([4, 5, 6]).write(to: thumb)
        defer {
            try? FileManager.default.removeItem(at: media)
            try? FileManager.default.removeItem(at: thumb)
        }
        let r: CKRecord = record(Records.postType, "post-A")
        Records.attach(media: media, thumb: thumb, to: r)
        XCTAssertEqual((r[MediaAssetKey.media.rawValue] as? CKAsset)?.fileURL?.lastPathComponent, media.lastPathComponent)
        XCTAssertEqual((r[MediaAssetKey.thumb.rawValue] as? CKAsset)?.fileURL?.lastPathComponent, thumb.lastPathComponent)

        let textOnly: CKRecord = record(Records.postType, "post-B")
        Records.attach(media: nil, thumb: nil, to: textOnly)
        XCTAssertTrue(textOnly.changedKeys().isEmpty)
    }

    // MARK: - Vote rules on the Group record

    func testVoteRulesRoundTripAsAFlatList() {
        let rules: [VoteRuleChange] = [VoteRuleChange(fromDay: 1, rule: .twoThirds), VoteRuleChange(fromDay: 5, rule: .everyone)]
        let r: CKRecord = CKRecord(recordType: Records.groupType, recordID: Records.groupRecordID(id))
        XCTAssertNil(Records.voteRules(r))
        XCTAssertNil(Records.groupInfo(from: r, id: id).voteRules)

        Records.apply(voteRules: rules, to: r)
        XCTAssertEqual(storedNumbers(r, "voteRules"), [1, 2, 5, 3])
        XCTAssertEqual(Records.voteRules(r), rules)
        XCTAssertEqual(Records.groupInfo(from: r, id: id).voteRules, rules)

        // An empty log clears the field, which reads as "More than half" from day 0.
        Records.apply(voteRules: [], to: r)
        XCTAssertNil(r.object(forKey: "voteRules"))
        XCTAssertNil(Records.voteRules(r))
    }

    func testMalformedVoteRulesAreDroppedOrClamped() {
        let r: CKRecord = record(Records.groupType, Records.groupRecordName)
        r["voteRules"] = numbers([-3, 2, 4, 9, 6, 3, 8])
        XCTAssertEqual(Records.voteRules(r), [VoteRuleChange(fromDay: 0, rule: .twoThirds),
                                              VoteRuleChange(fromDay: 6, rule: .everyone)])
        r["voteRules"] = numbers([7])
        XCTAssertEqual(Records.voteRules(r), [])
    }

    func testGroupApplyNeverWritesVoteRules() {
        let rules: [VoteRuleChange] = [VoteRuleChange(fromDay: 3, rule: .everyone)]
        let fresh: CKRecord = CKRecord(recordType: Records.groupType, recordID: Records.groupRecordID(id))
        Records.apply(makeGroup(voteRules: rules), to: fresh)
        XCTAssertFalse(fresh.changedKeys().contains("voteRules"))

        // A stale GroupInfo (no log, or an older one) leaves the stored log alone.
        Records.apply(voteRules: rules, to: fresh)
        Records.apply(makeGroup(voteRules: nil), to: fresh)
        Records.apply(makeGroup(voteRules: [VoteRuleChange(fromDay: 1, rule: .majority)]), to: fresh)
        XCTAssertEqual(Records.voteRules(fresh), rules)
    }

    // MARK: - The zone fetch's keys

    func testSnapshotKeysCoverEveryFieldButTheAssets() {
        let keys: Set<String> = Set(Records.snapshotKeys)
        XCTAssertEqual(keys.count, Records.snapshotKeys.count)
        XCTAssertFalse(keys.contains(MediaAssetKey.media.rawValue))
        XCTAssertFalse(keys.contains(MediaAssetKey.thumb.rawValue))

        let group: CKRecord = record(Records.groupType, Records.groupRecordName)
        Records.apply(makeGroup(endDay: 29), to: group)
        Records.apply(voteRules: [VoteRuleChange(fromDay: 2, rule: .twoThirds)], to: group)

        let member: CKRecord = record(Records.memberType, "member-maya")
        Records.apply(MemberInfo(userID: "maya", displayName: "Maya", vow: "I will run", joinedDay: 0, joinedEpoch: 0,
                                 leftDay: 4), to: member)

        let checkIn: CheckInInfo = CheckInInfo(userID: "maya", day: 2, epoch: 0, serverDate: nil)
        let checkInRecord: CKRecord = CKRecord(recordType: Records.checkInType,
                                               recordID: Records.checkInRecordID(checkIn, in: id))
        Records.apply(checkIn, to: checkInRecord)

        let excuse: CKRecord = record(Records.excuseType, "excuse-0-maya-3")
        Records.apply(ExcuseInfo(userID: "maya", day: 3, epoch: 0, text: "Sick", serverDate: nil), to: excuse)

        let vote: CKRecord = record(Records.voteType, "vote-0-ari-maya-3")
        Records.apply(VoteInfo(voterID: "ari", subjectID: "maya", day: 3, epoch: 0, counts: false, castDay: 3,
                               serverDate: nil), to: vote)

        let post: CKRecord = record(Records.postType, "post-1F2E")
        Records.apply(videoPost(), to: post)

        for r in [group, member, checkInRecord, excuse, vote, post] {
            for key in r.changedKeys() {
                XCTAssertTrue(keys.contains(key), "\(r.recordType).\(key) is missing from the zone fetch")
            }
        }
    }
}
