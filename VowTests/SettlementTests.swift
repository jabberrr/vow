import XCTest
@testable import Vow

final class SettlementTests: XCTestCase {

    // MARK: - Fixtures

    /// 2026-01-01T00:00:00Z = 2025-12-31 19:00 in New York, so day 0 is Dec 31 local.
    private let created: Date = Date(timeIntervalSince1970: 1_767_225_600)
    private let ny: String = "America/New_York"
    private let anyNow: Date = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeGroup(isTest: Bool = true, testDay: Int = 0, stake: Int = 2, epoch: Int = 0) -> GroupInfo {
        return GroupInfo(id: GroupID(zoneName: "group-test", ownerName: "owner"),
                         name: "Test",
                         stake: stake,
                         createdAt: created,
                         timeZoneID: ny,
                         isTest: isTest,
                         testDay: testDay,
                         epoch: epoch,
                         ownerUserID: "me",
                         shareURL: nil)
    }

    private func member(_ id: String, _ name: String, joinedDay: Int = 0, joinedEpoch: Int = 0, leftDay: Int? = nil) -> MemberInfo {
        return MemberInfo(userID: id, displayName: name, vow: "I will read", joinedDay: joinedDay,
                          joinedEpoch: joinedEpoch, leftDay: leftDay)
    }

    private func checkIn(_ id: String, _ day: Int, epoch: Int = 0, at seconds: Double? = nil) -> CheckInInfo {
        var date: Date? = nil
        if let s: Double = seconds {
            date = Date(timeIntervalSince1970: s)
        }
        return CheckInInfo(userID: id, day: day, epoch: epoch, serverDate: date)
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

    private func texts(_ s: GroupSummary) -> [String] {
        var out: [String] = []
        for line in s.ledger {
            out.append(line.text)
        }
        return out
    }

    private let minus: String = "\u{2212}"

    // MARK: - Splitting

    func testSplitAmongKeepersNetsSumToZero() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya"), member("theo", "Theo"), member("zed", "Zed")]
        let s: GroupSummary = summarize(makeGroup(testDay: 1), members,
                                        [checkIn("me", 0), checkIn("maya", 0), checkIn("theo", 0)])
        XCTAssertEqual(s.currentDay, 1)
        XCTAssertEqual(s.pot, 0, accuracy: 1e-9)
        XCTAssertEqual(s.totalForfeited, 2, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "theo")?.net ?? 99, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "zed")?.net ?? 99, -2, accuracy: 1e-9)
        var sum: Double = 0
        for m in s.standings {
            sum += m.net
        }
        XCTAssertEqual(sum, 0, accuracy: 1e-9)

        let t: [String] = texts(s)
        XCTAssertEqual(t.count, 8)
        XCTAssertEqual(Array(t.prefix(4)), [
            "Day 1 · You collect +0.67 pts",
            "Day 1 · Pot split 3 ways · +0.67 pts each",
            "Day 1 · Zed missed · \(minus)2 pts",
            "Day 1 · You kept"
        ])
        XCTAssertTrue(t.contains("Day 1 · You joined"))
        XCTAssertTrue(t.contains("Day 1 · Maya joined"))
        XCTAssertEqual(s.ledger[0].kind, .payout)
        XCTAssertEqual(s.ledger[0].amount ?? 0, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(s.ledger[1].kind, .split)
        XCTAssertNil(s.ledger[1].amount)
        XCTAssertEqual(s.ledger[2].kind, .forfeit)
        XCTAssertEqual(s.ledger[2].id, "d0-forfeit-zed")
        XCTAssertNil(s.ledger[2].amount)

        // Viewer first, then by name.
        XCTAssertEqual(s.standings.map { $0.userID }, ["me", "maya", "theo", "zed"])
        XCTAssertEqual(s.viewer?.userID, "me")
        XCTAssertEqual(s.cycle, 1)
        XCTAssertEqual(s.dayInCycle, 2)
        XCTAssertEqual(s.glyphNumber, 2)
    }

    func testNobodyKeptCarriesThenLaterSplitIncludesCarry() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya")]
        let checkIns: [CheckInInfo] = [checkIn("me", 1), checkIn("me", 2), checkIn("maya", 2)]
        let s: GroupSummary = summarize(makeGroup(testDay: 3, stake: 5), members, checkIns)
        XCTAssertEqual(s.standings.count, 2)
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 10, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, -10, accuracy: 1e-9)
        XCTAssertEqual(s.pot, 0, accuracy: 1e-9)
        XCTAssertEqual(s.totalForfeited, 15, accuracy: 1e-9)
        XCTAssertEqual(texts(s), [
            "Day 3 · You kept",
            "Day 2 · You collect +15 pts",
            "Day 2 · Pot split 1 way · +15 pts each",
            "Day 2 · Maya missed · \(minus)5 pts",
            "Day 2 · You kept",
            "Day 1 · Nobody kept · pot carries 10 pts",
            "Day 1 · Maya missed · \(minus)5 pts",
            "Day 1 · You missed · \(minus)5 pts",
            "Day 1 · Maya joined",
            "Day 1 · You joined"
        ])
        let missed: LedgerLine = s.ledger[7]
        XCTAssertEqual(missed.kind, .missed)
        XCTAssertEqual(missed.amount ?? 0, -5, accuracy: 1e-9)
        XCTAssertEqual(s.ledger[5].kind, .carry)
    }

    func testPotStillCarriedAfterLastClosedDay() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya")]
        let s: GroupSummary = summarize(makeGroup(testDay: 2, stake: 5), members, [checkIn("me", 0)])
        XCTAssertEqual(s.pot, 10, accuracy: 1e-9)
        XCTAssertEqual(s.totalForfeited, 15, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 0, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, -10, accuracy: 1e-9)
        XCTAssertEqual(s.ledger.first?.text, "Day 2 · Nobody kept · pot carries 10 pts")
    }

    // MARK: - Membership

    func testJoinedDayRespected() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya", joinedDay: 2)]
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("me", 1), checkIn("me", 2), checkIn("me", 3)]
        let s: GroupSummary = summarize(makeGroup(testDay: 4), members, checkIns)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, -4, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.history ?? [], [DayOutcome.missed, DayOutcome.missed])
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 4, accuracy: 1e-9)
        XCTAssertEqual(s.totalForfeited, 4, accuracy: 1e-9)
        XCTAssertTrue(texts(s).contains("Day 3 · Maya joined"))
        XCTAssertFalse(texts(s).contains("Day 2 · Maya missed · \(minus)2 pts"))
    }

    func testLeftDayRespected() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya", leftDay: 2)]
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("me", 1), checkIn("me", 2), checkIn("me", 3),
                                       checkIn("maya", 0)]
        let s: GroupSummary = summarize(makeGroup(testDay: 4), members, checkIns)
        XCTAssertEqual(s.standings.count, 1)
        XCTAssertNil(standing(s, "maya"))
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 2, accuracy: 1e-9)
        XCTAssertEqual(s.totalForfeited, 2, accuracy: 1e-9)
        let t: [String] = texts(s)
        XCTAssertTrue(t.contains("Day 2 · Maya missed · \(minus)2 pts"))
        XCTAssertTrue(t.contains("Day 3 · Maya left"))
        XCTAssertFalse(t.contains("Day 3 · Maya missed · \(minus)2 pts"))
        XCTAssertFalse(t.contains("Day 4 · Maya missed · \(minus)2 pts"))
    }

    func testViewerNilWhenNotAMember() {
        let members: [MemberInfo] = [member("maya", "Maya")]
        let s: GroupSummary = summarize(makeGroup(testDay: 1), members, [], viewer: "stranger")
        XCTAssertNil(s.viewer)
        XCTAssertEqual(s.standings.count, 1)
    }

    // MARK: - Epochs

    func testEpochFilteringAndEffectiveJoinedDay() {
        let members: [MemberInfo] = [member("me", "Ari", joinedDay: 5, joinedEpoch: 0),
                                     member("maya", "Maya", joinedDay: 1, joinedEpoch: 1)]
        let checkIns: [CheckInInfo] = [checkIn("me", 0, epoch: 0), checkIn("me", 1, epoch: 0),
                                       checkIn("me", 0, epoch: 1), checkIn("maya", 1, epoch: 1),
                                       checkIn("maya", 0, epoch: 0)]
        let s: GroupSummary = summarize(makeGroup(testDay: 2, epoch: 1), members, checkIns)
        XCTAssertEqual(standing(s, "me")?.history ?? [], [DayOutcome.kept, DayOutcome.missed])
        XCTAssertEqual(standing(s, "me")?.net ?? 99, -2, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.history ?? [], [DayOutcome.kept])
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, 2, accuracy: 1e-9)
        XCTAssertTrue(texts(s).contains("Day 1 · You joined"))
        XCTAssertTrue(texts(s).contains("Day 2 · Maya joined"))
    }

    // MARK: - Check-in validity

    func testServerDateValidity() {
        let real: GroupInfo = makeGroup(isTest: false)
        // Day 0 is 2025-12-31 in New York; day 1 starts 2026-01-01 00:00 EST = 1_767_243_600.
        XCTAssertTrue(Settlement.isValid(checkIn("me", 0, at: 1_767_240_000), group: real))   // Dec 31 23:00
        XCTAssertTrue(Settlement.isValid(checkIn("me", 0, at: 1_767_243_900), group: real))   // 00:05 next day (grace)
        XCTAssertTrue(Settlement.isValid(checkIn("me", 0, at: 1_767_244_199), group: real))   // 00:09:59
        XCTAssertFalse(Settlement.isValid(checkIn("me", 0, at: 1_767_244_200), group: real))  // 00:10:00
        XCTAssertFalse(Settlement.isValid(checkIn("me", 0, at: 1_767_244_260), group: real))  // 00:11
        XCTAssertFalse(Settlement.isValid(checkIn("me", 0, at: 1_767_373_200), group: real))  // two days later
        XCTAssertFalse(Settlement.isValid(checkIn("me", 1, at: 1_767_229_200), group: real))  // early, for a future day
        XCTAssertTrue(Settlement.isValid(checkIn("me", 0), group: real))                      // pending
        XCTAssertFalse(Settlement.isValid(checkIn("me", 0, epoch: 1), group: real))           // wrong epoch

        let test: GroupInfo = makeGroup(isTest: true, testDay: 3)
        XCTAssertTrue(Settlement.isValid(checkIn("me", 2, at: 1_900_000_000), group: test))
    }

    func testLateCheckInRejectedAndPendingCountsInRealGroup() {
        let real: GroupInfo = makeGroup(isTest: false)
        let now: Date = Date(timeIntervalSince1970: 1_767_373_200)  // 2026-01-02 12:00 New York → day 2
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya")]
        let checkIns: [CheckInInfo] = [checkIn("me", 0, at: 1_767_240_000),
                                       checkIn("maya", 0, at: 1_767_244_800),  // 00:20 next day: too late
                                       checkIn("me", 1, at: 1_767_276_000),
                                       checkIn("maya", 1, at: 1_767_276_000),
                                       checkIn("maya", 2)]                      // pending, today
        let s: GroupSummary = summarize(real, members, checkIns, now: now)
        XCTAssertEqual(s.currentDay, 2)
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 2, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, -2, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.history ?? [], [DayOutcome.missed, DayOutcome.kept])
        XCTAssertEqual(standing(s, "maya")?.checkedInToday, true)
        XCTAssertEqual(standing(s, "maya")?.streak, 2)
        XCTAssertEqual(standing(s, "me")?.checkedInToday, false)
    }

    func testDuplicateCheckInsCountOnce() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya")]
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("me", 0), checkIn("me", 0, at: 123)]
        let s: GroupSummary = summarize(makeGroup(testDay: 1), members, checkIns)
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 2, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "me")?.history ?? [], [DayOutcome.kept])
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, -2, accuracy: 1e-9)
        XCTAssertEqual(s.ledger.first?.text, "Day 1 · You collect +2 pts")
    }

    // MARK: - Streaks and status

    func testStreakBestAndMissedYesterday() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya"), member("theo", "Theo")]
        var checkIns: [CheckInInfo] = []
        let patterns: [(String, String)] = [("me", "KKKMKKK"), ("maya", "KKKKMKM"), ("theo", "MKKKKKK")]
        for (id, pattern) in patterns {
            var day: Int = 0
            for ch in pattern {
                if ch == "K" {
                    checkIns.append(checkIn(id, day))
                }
                day += 1
            }
        }
        checkIns.append(checkIn("me", 7))
        let s: GroupSummary = summarize(makeGroup(testDay: 7), members, checkIns)

        let me: MemberStanding? = standing(s, "me")
        XCTAssertEqual(me?.streak, 4)
        XCTAssertEqual(me?.bestStreak, 4)
        XCTAssertEqual(me?.checkedInToday, true)
        XCTAssertEqual(me?.missedYesterday, false)
        XCTAssertEqual(me?.history.count, 7)
        XCTAssertEqual(me?.status(isViewer: true), MemberStatus.checkedIn)

        let maya: MemberStanding? = standing(s, "maya")
        XCTAssertEqual(maya?.streak, 0)
        XCTAssertEqual(maya?.bestStreak, 4)
        XCTAssertEqual(maya?.missedYesterday, true)
        XCTAssertEqual(maya?.status(isViewer: false), MemberStatus.missed)

        let theo: MemberStanding? = standing(s, "theo")
        XCTAssertEqual(theo?.streak, 6)
        XCTAssertEqual(theo?.bestStreak, 6)
        XCTAssertEqual(theo?.missedYesterday, false)
        XCTAssertEqual(theo?.status(isViewer: false), MemberStatus.notYet)

        XCTAssertEqual(me?.net ?? 99, 1, accuracy: 1e-9)
        XCTAssertEqual(maya?.net ?? 99, -2, accuracy: 1e-9)
        XCTAssertEqual(theo?.net ?? 99, 1, accuracy: 1e-9)
        XCTAssertEqual(s.totalForfeited, 8, accuracy: 1e-9)
    }

    func testStatusForViewerAndOthers() {
        let notChecked: MemberStanding = MemberStanding(userID: "a", displayName: "A", vow: "", isActive: true,
                                                        net: 0, streak: 0, bestStreak: 0, history: [.missed],
                                                        checkedInToday: false, missedYesterday: true)
        XCTAssertEqual(notChecked.status(isViewer: true), MemberStatus.yourMove)
        XCTAssertEqual(notChecked.status(isViewer: false), MemberStatus.missed)

        let checked: MemberStanding = MemberStanding(userID: "b", displayName: "B", vow: "", isActive: true,
                                                     net: 0, streak: 1, bestStreak: 1, history: [],
                                                     checkedInToday: true, missedYesterday: false)
        XCTAssertEqual(checked.status(isViewer: true), MemberStatus.checkedIn)
        XCTAssertEqual(checked.status(isViewer: false), MemberStatus.checkedIn)

        let fresh: MemberStanding = MemberStanding(userID: "c", displayName: "C", vow: "", isActive: true,
                                                   net: 0, streak: 0, bestStreak: 0, history: [],
                                                   checkedInToday: false, missedYesterday: false)
        XCTAssertEqual(fresh.status(isViewer: false), MemberStatus.notYet)
        XCTAssertEqual(MemberStatus.yourMove.label, "your move")
        XCTAssertEqual(MemberStatus.checkedIn.label, "checked in")
    }
}
