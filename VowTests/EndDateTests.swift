import CloudKit
import XCTest
@testable import Vow

final class EndDateTests: XCTestCase {

    // MARK: - Fixtures

    /// 2026-01-01T00:00:00Z = 2025-12-31 19:00 in New York, so day 0 is Dec 31 local, day 1 Jan 1, day 2 Jan 2.
    private let created: Date = Date(timeIntervalSince1970: 1_767_225_600)
    private let ny: String = "America/New_York"
    private let anyNow: Date = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeGroup(isTest: Bool = true, testDay: Int = 0, stake: Int = 2, endDay: Int? = nil) -> GroupInfo {
        return GroupInfo(id: GroupID(zoneName: "group-end", ownerName: "owner"),
                         name: "End",
                         stake: stake,
                         createdAt: created,
                         timeZoneID: ny,
                         isTest: isTest,
                         testDay: testDay,
                         epoch: 0,
                         ownerUserID: "me",
                         shareURL: nil,
                         endDay: endDay)
    }

    private func member(_ id: String, _ name: String, joinedDay: Int = 0) -> MemberInfo {
        return MemberInfo(userID: id, displayName: name, vow: "I will read", joinedDay: joinedDay,
                          joinedEpoch: 0, leftDay: nil)
    }

    private func checkIn(_ id: String, _ day: Int, at seconds: Double? = nil) -> CheckInInfo {
        var date: Date? = nil
        if let s: Double = seconds {
            date = Date(timeIntervalSince1970: s)
        }
        return CheckInInfo(userID: id, day: day, epoch: 0, serverDate: date)
    }

    private func summarize(_ group: GroupInfo, _ members: [MemberInfo], _ checkIns: [CheckInInfo],
                           viewer: String = "me", now: Date? = nil) -> GroupSummary {
        let snapshot: GroupSnapshot = GroupSnapshot(group: group, members: members, checkIns: checkIns,
                                                    fetchedAt: created)
        return Settlement.summarize(snapshot, viewerID: viewer, now: now ?? anyNow)
    }

    private func standing(_ s: GroupSummary, _ id: String) -> MemberStanding? {
        for m in s.standings where m.userID == id {
            return m
        }
        return nil
    }

    private let pair: [MemberInfo] = [
        MemberInfo(userID: "me", displayName: "Ari", vow: "I will read", joinedDay: 0, joinedEpoch: 0, leftDay: nil),
        MemberInfo(userID: "maya", displayName: "Maya", vow: "I will run", joinedDay: 0, joinedEpoch: 0, leftDay: nil)
    ]

    // MARK: - Settlement stops at the final day

    func testUnfinishedVowSettlesExactlyAsWithoutEnd() {
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("maya", 1), checkIn("me", 2), checkIn("maya", 2),
                                       checkIn("me", 4), checkIn("me", 12)]
        for day in 0...10 {
            let plain: GroupSummary = summarize(makeGroup(testDay: day), pair, checkIns)
            let ending: GroupSummary = summarize(makeGroup(testDay: day, endDay: 10), pair, checkIns)
            XCTAssertFalse(ending.isFinished, "day \(day)")
            XCTAssertEqual(ending.endDay, 10)
            XCTAssertNil(plain.endDay)
            XCTAssertFalse(plain.isFinished)
            XCTAssertEqual(ending.currentDay, plain.currentDay, "day \(day)")
            XCTAssertEqual(ending.pot, plain.pot, accuracy: 1e-9)
            XCTAssertEqual(ending.totalForfeited, plain.totalForfeited, accuracy: 1e-9)
            XCTAssertEqual(ending.standings, plain.standings, "day \(day)")
            XCTAssertEqual(ending.ledger, plain.ledger, "day \(day)")
        }
    }

    func testFinishedVowSettlesThroughFinalDayAndNothingAfter() {
        var checkIns: [CheckInInfo] = []
        for day in 0...5 {
            checkIns.append(checkIn("me", day))
        }
        let ended: GroupSummary = summarize(makeGroup(testDay: 6, endDay: 2), pair, checkIns)
        // The same records seen on day 3 without an end: days 0...2 closed, day 3 open (and not settled).
        let reference: GroupSummary = summarize(makeGroup(testDay: 3), pair, checkIns)

        XCTAssertTrue(ended.isFinished)
        XCTAssertEqual(ended.endDay, 2)
        XCTAssertEqual(ended.currentDay, 3)
        XCTAssertEqual(ended.totalForfeited, 6, accuracy: 1e-9)
        XCTAssertEqual(ended.pot, 0, accuracy: 1e-9)
        XCTAssertEqual(ended.totalForfeited, reference.totalForfeited, accuracy: 1e-9)
        XCTAssertEqual(ended.ledger, reference.ledger)
        XCTAssertEqual(standing(ended, "me")?.net ?? 99, 6, accuracy: 1e-9)
        XCTAssertEqual(standing(ended, "maya")?.net ?? 99, -6, accuracy: 1e-9)
        XCTAssertEqual(standing(ended, "me")?.net ?? 99, standing(reference, "me")?.net ?? 0, accuracy: 1e-9)
        XCTAssertEqual(standing(ended, "me")?.history ?? [], [DayOutcome.kept, DayOutcome.kept, DayOutcome.kept])
        XCTAssertEqual(standing(ended, "maya")?.history ?? [], [DayOutcome.missed, DayOutcome.missed, DayOutcome.missed])
        for line in ended.ledger {
            XCTAssertLessThanOrEqual(line.day, 2, line.text)
        }
    }

    func testPotStopsAtTheFinalDay() {
        // Day 0: Maya misses, you collect 2. Day 1 (final): both miss, the pot carries 4.
        // Check-ins on days 2 and 3 come after the end, so nobody collects the carry.
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("me", 2), checkIn("maya", 2), checkIn("me", 3)]
        let s: GroupSummary = summarize(makeGroup(testDay: 5, endDay: 1), pair, checkIns)
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.pot, 4, accuracy: 1e-9)
        XCTAssertEqual(s.totalForfeited, 6, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 0, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, -4, accuracy: 1e-9)
        XCTAssertEqual(s.ledger.first?.text, "Day 2 · Nobody kept · pot carries 4 pts")
    }

    func testNoMembershipEventsAfterTheFinalDay() {
        let members: [MemberInfo] = [member("me", "Ari"), member("late", "Lou", joinedDay: 3)]
        let s: GroupSummary = summarize(makeGroup(testDay: 4, endDay: 2), members, [checkIn("me", 0)])
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(standing(s, "late")?.history ?? [DayOutcome.kept], [])
        for line in s.ledger {
            XCTAssertLessThanOrEqual(line.day, 2, line.text)
        }
        XCTAssertEqual(s.totalForfeited, 4, accuracy: 1e-9)
    }

    // MARK: - Check-in validity

    func testCheckInAfterFinalDayIsInvalid() {
        let real: GroupInfo = makeGroup(isTest: false, endDay: 2)
        XCTAssertTrue(Settlement.isValid(checkIn("me", 2), group: real))                       // pending, final day
        XCTAssertFalse(Settlement.isValid(checkIn("me", 3), group: real))                      // pending, after the end
        XCTAssertTrue(Settlement.isValid(checkIn("me", 2, at: 1_767_373_200), group: real))    // Jan 2 12:00, final day
        XCTAssertTrue(Settlement.isValid(checkIn("me", 2, at: 1_767_416_700), group: real))    // Jan 3 00:05: grace still applies
        XCTAssertFalse(Settlement.isValid(checkIn("me", 3, at: 1_767_459_600), group: real))   // Jan 3 12:00, day 3
        XCTAssertTrue(Settlement.isValid(checkIn("me", 3, at: 1_767_459_600), group: makeGroup(isTest: false)))

        let test: GroupInfo = makeGroup(isTest: true, testDay: 4, endDay: 2)
        XCTAssertTrue(Settlement.isValid(checkIn("me", 2, at: 1_900_000_000), group: test))
        XCTAssertFalse(Settlement.isValid(checkIn("me", 3, at: 1_900_000_000), group: test))
    }

    // MARK: - isFinished

    func testIsFinishedBoundaries() {
        XCTAssertFalse(EndDate.isFinished(makeGroup(testDay: 0, endDay: 2), now: anyNow))
        XCTAssertFalse(EndDate.isFinished(makeGroup(testDay: 2, endDay: 2), now: anyNow))
        XCTAssertTrue(EndDate.isFinished(makeGroup(testDay: 3, endDay: 2), now: anyNow))
        XCTAssertTrue(EndDate.isFinished(makeGroup(testDay: 40, endDay: 2), now: anyNow))
        XCTAssertFalse(EndDate.isFinished(makeGroup(testDay: 500), now: anyNow))

        // Real group: the final day (1) is 2026-01-01 in New York.
        let real: GroupInfo = makeGroup(isTest: false, endDay: 1)
        let lastMinute: Date = Date(timeIntervalSince1970: 1_767_329_940)   // 2026-01-01 23:59 EST
        let nextDay: Date = Date(timeIntervalSince1970: 1_767_330_030)      // 2026-01-02 00:00:30 EST
        XCTAssertFalse(EndDate.isFinished(real, now: lastMinute))
        XCTAssertTrue(EndDate.isFinished(real, now: nextDay))
        XCTAssertFalse(EndDate.isFinished(makeGroup(isTest: false), now: nextDay))

        let open: GroupSummary = summarize(real, pair, [], now: lastMinute)
        XCTAssertFalse(open.isFinished)
        XCTAssertEqual(open.currentDay, 1)
        let done: GroupSummary = summarize(real, pair, [], now: nextDay)
        XCTAssertTrue(done.isFinished)
        XCTAssertEqual(done.currentDay, 2)
        let muchLater: GroupSummary = summarize(real, pair, [], now: anyNow)
        XCTAssertTrue(muchLater.isFinished)
        XCTAssertEqual(muchLater.currentDay, 2)
        XCTAssertEqual(muchLater.totalForfeited, done.totalForfeited, accuracy: 1e-9)
    }

    // MARK: - Nothing is open after the end

    func testFinishedSummaryHasNoTodayAndIsNotOpen() {
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("me", 3), checkIn("maya", 3)]
        let s: GroupSummary = summarize(makeGroup(testDay: 3, endDay: 2), pair, checkIns)
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.viewer?.checkedInToday, false)
        for m in s.standings {
            XCTAssertFalse(m.checkedInToday, m.userID)
        }
        XCTAssertFalse(Digest.isOpen(s))

        // On the final day itself the vow is open until you check in.
        let lastDay: GroupSummary = summarize(makeGroup(testDay: 2, endDay: 2), pair, [checkIn("me", 0)])
        XCTAssertFalse(lastDay.isFinished)
        XCTAssertTrue(Digest.isOpen(lastDay))
        let lastDayKept: GroupSummary = summarize(makeGroup(testDay: 2, endDay: 2), pair, [checkIn("me", 2)])
        XCTAssertFalse(Digest.isOpen(lastDayKept))

        // A hand-built summary: isFinished alone closes it.
        let viewer: MemberStanding = MemberStanding(userID: "me", displayName: "Me", vow: "I will read", isActive: true,
                                                    net: 0, streak: 0, bestStreak: 0, history: [.missed],
                                                    checkedInToday: false, missedYesterday: true)
        let manual: GroupSummary = GroupSummary(currentDay: 3, cycle: 1, dayInCycle: 4, glyphNumber: 4, pot: 0,
                                                totalForfeited: 0, standings: [viewer], ledger: [], viewer: viewer,
                                                endDay: 2, isFinished: true)
        XCTAssertFalse(Digest.isOpen(manual))
    }

    func testStreakAtTheEndIsTrailingKeptDaysThroughFinalDay() {
        // You: missed day 0, kept 1...3 (3 is the final day); later check-ins don't count.
        let checkIns: [CheckInInfo] = [checkIn("me", 1), checkIn("me", 2), checkIn("me", 3), checkIn("me", 4),
                                       checkIn("me", 5), checkIn("maya", 0)]
        let s: GroupSummary = summarize(makeGroup(testDay: 6, endDay: 3), pair, checkIns)
        let me: MemberStanding? = standing(s, "me")
        XCTAssertEqual(me?.history ?? [], [DayOutcome.missed, DayOutcome.kept, DayOutcome.kept, DayOutcome.kept])
        XCTAssertEqual(me?.streak, 3)
        XCTAssertEqual(me?.bestStreak, 3)
        XCTAssertEqual(me?.checkedInToday, false)
        XCTAssertEqual(standing(s, "maya")?.streak, 0)
        XCTAssertEqual(standing(s, "maya")?.bestStreak, 1)
    }

    // MARK: - Day counter and final date

    func testDayCounter() {
        let first: (day: Int, total: Int)? = EndDate.dayCounter(summarize(makeGroup(testDay: 0, endDay: 9), pair, []))
        XCTAssertEqual(first?.day, 1)
        XCTAssertEqual(first?.total, 10)

        let middle: (day: Int, total: Int)? = EndDate.dayCounter(summarize(makeGroup(testDay: 3, endDay: 9), pair, []))
        XCTAssertEqual(middle?.day, 4)
        XCTAssertEqual(middle?.total, 10)

        let last: (day: Int, total: Int)? = EndDate.dayCounter(summarize(makeGroup(testDay: 9, endDay: 9), pair, []))
        XCTAssertEqual(last?.day, 10)
        XCTAssertEqual(last?.total, 10)

        XCTAssertNil(EndDate.dayCounter(summarize(makeGroup(testDay: 10, endDay: 9), pair, [])))
        XCTAssertNil(EndDate.dayCounter(summarize(makeGroup(testDay: 3), pair, [])))
    }

    func testFinalDate() {
        // Final day 2 = 2026-01-02 00:00 EST.
        XCTAssertEqual(EndDate.finalDate(makeGroup(isTest: false, endDay: 2)), Date(timeIntervalSince1970: 1_767_330_000))
        XCTAssertNil(EndDate.finalDate(makeGroup(isTest: false)))

        // Across spring forward: created 2026-03-07 12:00 EST, final day 2 = 2026-03-09 00:00 EDT.
        var dst: GroupInfo = makeGroup(isTest: false, endDay: 2)
        dst.createdAt = Date(timeIntervalSince1970: 1_772_902_800)
        XCTAssertEqual(EndDate.finalDate(dst), Date(timeIntervalSince1970: 1_773_028_800))
    }

    // MARK: - Persistence

    func testGroupInfoDecodesWithoutEndDay() throws {
        let json: String = """
        {
          "group": {
            "id": {"zoneName": "group-old", "ownerName": "owner"},
            "name": "Old",
            "stake": 2,
            "createdAt": 0,
            "timeZoneID": "America/New_York",
            "isTest": false,
            "testDay": 0,
            "epoch": 0,
            "ownerUserID": "me"
          },
          "members": [],
          "checkIns": [],
          "fetchedAt": 0
        }
        """
        let old: GroupSnapshot = try JSONDecoder().decode(GroupSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(old.group.endDay)
        XCTAssertNil(old.group.shareURL)
        XCTAssertEqual(old.group.name, "Old")
        XCTAssertEqual(old.group.stake, 2)

        let withEnd: GroupInfo = makeGroup(endDay: 29)
        let data: Data = try JSONEncoder().encode(withEnd)
        let back: GroupInfo = try JSONDecoder().decode(GroupInfo.self, from: data)
        XCTAssertEqual(back, withEnd)
        XCTAssertEqual(back.endDay, 29)

        let noEnd: GroupInfo = makeGroup()
        let plainData: Data = try JSONEncoder().encode(noEnd)
        let plain: GroupInfo = try JSONDecoder().decode(GroupInfo.self, from: plainData)
        XCTAssertNil(plain.endDay)
        XCTAssertEqual(plain, noEnd)
    }

    func testRecordMappingOfEndDay() {
        let id: GroupID = GroupID(zoneName: "group-end", ownerName: "owner")
        let record: CKRecord = CKRecord(recordType: Records.groupType, recordID: Records.groupRecordID(id))
        Records.apply(makeGroup(endDay: 12), to: record)
        XCTAssertEqual(Records.int(record, "endDay"), 12)
        XCTAssertEqual(Records.groupInfo(from: record, id: id).endDay, 12)

        // Clearing removes the value.
        Records.apply(makeGroup(), to: record)
        XCTAssertNil(Records.int(record, "endDay"))
        XCTAssertNil(Records.groupInfo(from: record, id: id).endDay)

        // A group without an end never touches the field.
        let fresh: CKRecord = CKRecord(recordType: Records.groupType, recordID: Records.groupRecordID(id))
        Records.apply(makeGroup(), to: fresh)
        XCTAssertFalse(fresh.changedKeys().contains("endDay"))
        XCTAssertNil(Records.groupInfo(from: fresh, id: id).endDay)

        // Malformed values are clamped.
        record["endDay"] = Records.number(-4)
        XCTAssertEqual(Records.endDay(record), 0)
        record["endDay"] = Records.number(10_000_000)
        XCTAssertEqual(Records.endDay(record), EndDate.maxEndDay)
    }
}
