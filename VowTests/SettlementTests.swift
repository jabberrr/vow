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

    private func excuse(_ id: String, _ day: Int, epoch: Int = 0, at seconds: Double? = nil) -> ExcuseInfo {
        var date: Date? = nil
        if let s: Double = seconds {
            date = Date(timeIntervalSince1970: s)
        }
        return ExcuseInfo(userID: id, day: day, epoch: epoch, text: "Sick", serverDate: date)
    }

    /// A pending "Doesn't count" vote by `voter` on `subject`'s claim for `day`, cast that day.
    private func against(_ voter: String, _ subject: String, _ day: Int) -> VoteInfo {
        return VoteInfo(voterID: voter, subjectID: subject, day: day, epoch: 0, counts: false, castDay: day,
                        serverDate: nil)
    }

    private func summarize(_ group: GroupInfo, _ members: [MemberInfo], _ checkIns: [CheckInInfo],
                           excuses: [ExcuseInfo] = [], votes: [VoteInfo] = [],
                           viewer: String = "me", now: Date? = nil) -> GroupSummary {
        let snapshot: GroupSnapshot = GroupSnapshot(group: group, members: members, checkIns: checkIns,
                                                    fetchedAt: created, excuses: excuses, votes: votes)
        return Settlement.summarize(snapshot, viewerID: viewer, now: now ?? anyNow)
    }

    private func standing(_ s: GroupSummary, _ id: String) -> MemberStanding? {
        for m in s.standings where m.userID == id {
            return m
        }
        return nil
    }

    private let ari: LedgerPerson = LedgerPerson(userID: "me", name: "Ari")
    private let maya: LedgerPerson = LedgerPerson(userID: "maya", name: "Maya")
    private let theo: LedgerPerson = LedgerPerson(userID: "theo", name: "Theo")
    private let zed: LedgerPerson = LedgerPerson(userID: "zed", name: "Zed")
    private let lou: LedgerPerson = LedgerPerson(userID: "lou", name: "Lou")

    private func forfeit(_ person: LedgerPerson, _ reason: Forfeit.Reason = .missed, amount: Double = 2) -> Forfeit {
        return Forfeit(person: person, reason: reason, amount: amount)
    }

    /// A closed day of the ledger; the money defaults to none.
    private func closed(_ day: Int, joined: [LedgerPerson] = [], left: [LedgerPerson] = [], kept: [LedgerPerson] = [],
                        excused: [LedgerPerson] = [], forfeits: [Forfeit] = [], carriedIn: Double = 0, share: Double = 0,
                        carriedOut: Double = 0) -> LedgerDay {
        return LedgerDay(day: day, isClosed: true, joined: joined, left: left, kept: kept, excused: excused,
                         forfeits: forfeits, carriedIn: carriedIn, share: share, carriedOut: carriedOut)
    }

    /// Listed day `day` of the ledger.
    private func entry(_ s: GroupSummary, _ day: Int) throws -> LedgerDay {
        let found: LedgerDay? = s.days.first { (d: LedgerDay) -> Bool in d.day == day }
        return try XCTUnwrap(found, "day \(day) isn't listed")
    }

    // MARK: - Splitting

    func testSplitAmongKeepersNetsSumToZero() throws {
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

        // Today (day 1) has no joins or leaves, so only day 0 is listed.
        XCTAssertEqual(s.days.count, 1)
        let d: LedgerDay = try entry(s, 0)
        XCTAssertTrue(d.isClosed)
        XCTAssertEqual(d.joined, [ari, maya, theo, zed])
        XCTAssertEqual(d.kept, [ari, maya, theo])
        XCTAssertEqual(d.excused, [])
        XCTAssertEqual(d.forfeits, [forfeit(zed)])
        XCTAssertEqual(d.carriedIn, 0, accuracy: 1e-9)
        XCTAssertEqual(d.share, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(d.carriedOut, 0, accuracy: 1e-9)
        XCTAssertEqual(Digest.viewerChange(s.days, day: 0, viewerID: "me"), 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(Digest.viewerChange(s.days, day: 0, viewerID: "zed"), -2, accuracy: 1e-9)

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
        XCTAssertEqual(s.days, [
            closed(2, kept: [ari, maya]),
            closed(1, kept: [ari], forfeits: [forfeit(maya, amount: 5)], carriedIn: 10, share: 15),
            closed(0, joined: [ari, maya], forfeits: [forfeit(ari, amount: 5), forfeit(maya, amount: 5)], carriedOut: 10)
        ])
        XCTAssertEqual(Digest.viewerChange(s.days, day: 0, viewerID: "me"), -5, accuracy: 1e-9)
        XCTAssertEqual(Digest.viewerChange(s.days, day: 1, viewerID: "me"), 15, accuracy: 1e-9)
    }

    func testPotStillCarriedAfterLastClosedDay() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya")]
        let s: GroupSummary = summarize(makeGroup(testDay: 2, stake: 5), members, [checkIn("me", 0)])
        XCTAssertEqual(s.pot, 10, accuracy: 1e-9)
        XCTAssertEqual(s.totalForfeited, 15, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 0, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, -10, accuracy: 1e-9)
        XCTAssertEqual(s.days.first, closed(1, forfeits: [forfeit(ari, amount: 5), forfeit(maya, amount: 5)], carriedOut: 10))
    }

    // MARK: - Membership

    func testJoinedDayRespected() throws {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya", joinedDay: 2)]
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("me", 1), checkIn("me", 2), checkIn("me", 3)]
        let s: GroupSummary = summarize(makeGroup(testDay: 4), members, checkIns)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, -4, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.history ?? [], [DayOutcome.missed, DayOutcome.missed])
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 4, accuracy: 1e-9)
        XCTAssertEqual(s.totalForfeited, 4, accuracy: 1e-9)
        XCTAssertEqual(try entry(s, 0).joined, [ari])
        XCTAssertEqual(try entry(s, 1).forfeits, [])
        XCTAssertEqual(try entry(s, 2).joined, [maya])
        XCTAssertEqual(try entry(s, 2).forfeits, [forfeit(maya)])
    }

    func testLeftDayRespected() throws {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya", leftDay: 2)]
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("me", 1), checkIn("me", 2), checkIn("me", 3),
                                       checkIn("maya", 0)]
        let s: GroupSummary = summarize(makeGroup(testDay: 4), members, checkIns)
        XCTAssertEqual(s.standings.count, 1)
        XCTAssertNil(standing(s, "maya"))
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 2, accuracy: 1e-9)
        XCTAssertEqual(s.totalForfeited, 2, accuracy: 1e-9)
        XCTAssertEqual(try entry(s, 1).forfeits, [forfeit(maya)])
        XCTAssertEqual(try entry(s, 2).left, [maya])
        XCTAssertEqual(try entry(s, 2).forfeits, [])
        XCTAssertEqual(try entry(s, 3).forfeits, [])
        XCTAssertEqual(try entry(s, 3).left, [])
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
        XCTAssertEqual(s.days, [
            closed(1, joined: [maya], kept: [maya], forfeits: [forfeit(ari)], share: 2),
            closed(0, joined: [ari], kept: [ari])
        ])
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
        XCTAssertEqual(s.days, [closed(0, joined: [ari, maya], kept: [ari], forfeits: [forfeit(maya)], share: 2)])
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

    // MARK: - Overruled claims

    func testOverruledCheckInIsAMissWithStakeAndPot() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya"), member("theo", "Theo")]
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("maya", 0), checkIn("theo", 0)]
        let votes: [VoteInfo] = [against("me", "maya", 0), against("theo", "maya", 0)]
        let s: GroupSummary = summarize(makeGroup(testDay: 1), members, checkIns, votes: votes)

        XCTAssertEqual(s.totalForfeited, 2, accuracy: 1e-9)
        XCTAssertEqual(s.pot, 0, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 1, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "theo")?.net ?? 99, 1, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, -2, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.history ?? [], [DayOutcome.missed])
        XCTAssertEqual(standing(s, "maya")?.streak, 0)
        XCTAssertEqual(standing(s, "maya")?.missedYesterday, true)
        XCTAssertEqual(s.days, [closed(0, joined: [ari, maya, theo], kept: [ari, theo],
                                       forfeits: [forfeit(maya, .checkInOverruled)], share: 1)])

        // One "Doesn't count" of two voters isn't more than half: the check-in stands.
        let stands: GroupSummary = summarize(makeGroup(testDay: 1), members, checkIns, votes: [against("me", "maya", 0)])
        XCTAssertEqual(stands.totalForfeited, 0, accuracy: 1e-9)
        XCTAssertEqual(standing(stands, "maya")?.history ?? [], [DayOutcome.kept])
    }

    func testYourOverruledCheckInIsYourMiss() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya"), member("theo", "Theo")]
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("maya", 0), checkIn("theo", 0)]
        let votes: [VoteInfo] = [against("me", "maya", 0), against("theo", "maya", 0)]
        let s: GroupSummary = summarize(makeGroup(testDay: 1), members, checkIns, votes: votes, viewer: "maya")
        // The ledger reads the same for every viewer; only the UI says "You".
        XCTAssertEqual(s.days, summarize(makeGroup(testDay: 1), members, checkIns, votes: votes).days)
        XCTAssertEqual(s.viewer?.net ?? 99, -2, accuracy: 1e-9)
        XCTAssertEqual(Digest.viewerChange(s.days, day: 0, viewerID: "maya"), -2, accuracy: 1e-9)
        XCTAssertEqual(Digest.viewerChange(s.days, day: 0, viewerID: "me"), 1, accuracy: 1e-9)
    }

    func testOverruledExcuseIsAMiss() throws {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya"), member("theo", "Theo")]
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("theo", 0)]
        let votes: [VoteInfo] = [against("me", "maya", 0), against("theo", "maya", 0)]
        let s: GroupSummary = summarize(makeGroup(testDay: 1), members, checkIns, excuses: [excuse("maya", 0)],
                                        votes: votes)
        XCTAssertEqual(standing(s, "maya")?.history ?? [], [DayOutcome.missed])
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, -2, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 1, accuracy: 1e-9)
        let d: LedgerDay = try entry(s, 0)
        XCTAssertEqual(d.forfeits, [forfeit(maya, .excuseOverruled)])
        XCTAssertEqual(d.excused, [])
        XCTAssertEqual(d.kept, [ari, theo])

        let mine: GroupSummary = summarize(makeGroup(testDay: 1), members, checkIns, excuses: [excuse("maya", 0)],
                                           votes: votes, viewer: "maya")
        XCTAssertEqual(mine.days, s.days)
        XCTAssertEqual(Digest.viewerChange(mine.days, day: 0, viewerID: "maya"), -2, accuracy: 1e-9)
    }

    // MARK: - Excuses

    func testAcceptedExcuseSitsOutAndPausesTheStreak() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya"), member("theo", "Theo")]
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("maya", 0), checkIn("maya", 1), checkIn("me", 2)]
        let s: GroupSummary = summarize(makeGroup(testDay: 3), members, checkIns, excuses: [excuse("me", 1)])

        // Day 2: you sit out, so Theo's forfeit goes to Maya alone and you neither pay nor collect.
        XCTAssertEqual(s.days, [
            closed(2, kept: [ari], forfeits: [forfeit(maya), forfeit(theo)], share: 4),
            closed(1, kept: [maya], excused: [ari], forfeits: [forfeit(theo)], share: 2),
            closed(0, joined: [ari, maya, theo], kept: [ari, maya], forfeits: [forfeit(theo)], share: 1)
        ])
        XCTAssertEqual(Digest.viewerChange(s.days, day: 1, viewerID: "me"), 0, accuracy: 1e-9)
        XCTAssertEqual(Digest.viewerChange(s.days, day: 1, viewerID: "maya"), 2, accuracy: 1e-9)

        XCTAssertEqual(standing(s, "me")?.net ?? 99, 5, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, 1, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "theo")?.net ?? 99, -6, accuracy: 1e-9)
        XCTAssertEqual(s.totalForfeited, 8, accuracy: 1e-9)
        XCTAssertEqual(s.pot, 0, accuracy: 1e-9)

        let me: MemberStanding? = standing(s, "me")
        XCTAssertEqual(me?.history ?? [], [DayOutcome.kept, DayOutcome.excused, DayOutcome.kept])
        XCTAssertEqual(me?.streak, 2)
        XCTAssertEqual(me?.bestStreak, 2)
        XCTAssertEqual(me?.missedYesterday, false)

        let theirs: GroupSummary = summarize(makeGroup(testDay: 3), members, checkIns, excuses: [excuse("me", 1)],
                                             viewer: "theo")
        XCTAssertEqual(theirs.days, s.days)
    }

    func testEveryoneExcusedCarriesThePotUntouched() throws {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya")]
        let excuses: [ExcuseInfo] = [excuse("me", 1), excuse("maya", 1)]
        let s: GroupSummary = summarize(makeGroup(testDay: 3, stake: 5), members, [checkIn("me", 2)], excuses: excuses)
        XCTAssertEqual(s.days, [
            closed(2, kept: [ari], forfeits: [forfeit(maya, amount: 5)], carriedIn: 10, share: 15),
            closed(1, excused: [ari, maya], carriedIn: 10, carriedOut: 10),
            closed(0, joined: [ari, maya], forfeits: [forfeit(ari, amount: 5), forfeit(maya, amount: 5)], carriedOut: 10)
        ])
        // Day 1 moves nothing: no forfeits, no share, and the carry goes on as it came in.
        let sitOut: LedgerDay = try entry(s, 1)
        XCTAssertTrue(sitOut.forfeits.isEmpty)
        XCTAssertEqual(sitOut.share, 0, accuracy: 1e-9)
        XCTAssertEqual(sitOut.carriedOut, sitOut.carriedIn, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 10, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, -10, accuracy: 1e-9)
        XCTAssertEqual(s.totalForfeited, 15, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "me")?.history ?? [], [DayOutcome.missed, DayOutcome.excused, DayOutcome.kept])
        XCTAssertEqual(standing(s, "me")?.streak, 1)
        XCTAssertEqual(standing(s, "maya")?.missedYesterday, true)

        // Before day 3 settles, the pot still holds day 1's 10 pts.
        let carried: GroupSummary = summarize(makeGroup(testDay: 2, stake: 5), members, [], excuses: excuses)
        XCTAssertEqual(carried.pot, 10, accuracy: 1e-9)
        XCTAssertEqual(carried.days.first, closed(1, excused: [ari, maya], carriedIn: 10, carriedOut: 10))
    }

    func testCheckInWinsOverAnExcuse() throws {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya")]
        let checkIns: [CheckInInfo] = [checkIn("maya", 0), checkIn("maya", 1)]
        let excuses: [ExcuseInfo] = [excuse("maya", 0), excuse("maya", 1)]
        let s: GroupSummary = summarize(makeGroup(testDay: 1), members, checkIns, excuses: excuses)
        let hers: MemberStanding? = standing(s, "maya")
        XCTAssertEqual(hers?.history ?? [], [DayOutcome.kept])
        XCTAssertEqual(hers?.checkedInToday, true)
        XCTAssertEqual(hers?.excusedToday, false)
        XCTAssertEqual(hers?.streak, 2)
        XCTAssertEqual(try entry(s, 0).kept, [maya])
        XCTAssertEqual(try entry(s, 0).excused, [])

        // Overruling the check-in leaves a miss: the excuse doesn't stand in for it.
        let overruled: GroupSummary = summarize(makeGroup(testDay: 1), members, checkIns, excuses: excuses,
                                                votes: [against("me", "maya", 0)])
        XCTAssertEqual(standing(overruled, "maya")?.history ?? [], [DayOutcome.missed])
        XCTAssertEqual(try entry(overruled, 0).forfeits, [forfeit(ari), forfeit(maya, .checkInOverruled)])
        XCTAssertEqual(try entry(overruled, 0).excused, [])
    }

    func testExcuseValidityMatchesCheckIns() {
        let real: GroupInfo = makeGroup(isTest: false)
        // Day 0 is 2025-12-31 in New York; day 1 starts 2026-01-01 00:00 EST = 1_767_243_600.
        XCTAssertTrue(Settlement.isValid(excuse("me", 0, at: 1_767_240_000), group: real))    // Dec 31 23:00
        XCTAssertTrue(Settlement.isValid(excuse("me", 0, at: 1_767_244_199), group: real))    // 00:09:59 next day
        XCTAssertFalse(Settlement.isValid(excuse("me", 0, at: 1_767_244_200), group: real))   // 00:10:00
        XCTAssertFalse(Settlement.isValid(excuse("me", 1, at: 1_767_229_200), group: real))   // early, for a future day
        XCTAssertTrue(Settlement.isValid(excuse("me", 0), group: real))                       // pending
        XCTAssertFalse(Settlement.isValid(excuse("me", 0, epoch: 1), group: real))            // wrong epoch
        XCTAssertFalse(Settlement.isValid(excuse("me", -1), group: real))

        var ending: GroupInfo = makeGroup(isTest: false)
        ending.endDay = 2
        XCTAssertTrue(Settlement.isValid(excuse("me", 2), group: ending))
        XCTAssertFalse(Settlement.isValid(excuse("me", 3), group: ending))

        XCTAssertTrue(Settlement.isValid(excuse("me", 2, at: 1_900_000_000), group: makeGroup(testDay: 3)))

        // A late excuse is no excuse: the day is a miss.
        let now: Date = Date(timeIntervalSince1970: 1_767_373_200)  // 2026-01-02 12:00 New York → day 2
        let s: GroupSummary = summarize(real, [member("me", "Ari"), member("maya", "Maya")],
                                        [checkIn("maya", 0, at: 1_767_240_000)],
                                        excuses: [excuse("me", 0, at: 1_767_244_800)], now: now)  // 00:20 next day
        XCTAssertEqual(standing(s, "me")?.history ?? [], [DayOutcome.missed, DayOutcome.missed])
    }

    func testStreaksAndYesterdayFollowTheVerdict() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya"), member("theo", "Theo")]
        var checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("me", 1), checkIn("me", 3), checkIn("me", 4),
                                       checkIn("me", 5), checkIn("theo", 0), checkIn("theo", 3)]
        for day in 0...4 {
            checkIns.append(checkIn("maya", day))
        }
        let excuses: [ExcuseInfo] = [excuse("me", 2), excuse("theo", 2), excuse("theo", 4)]
        let votes: [VoteInfo] = [against("me", "maya", 4), against("theo", "maya", 4)]
        let s: GroupSummary = summarize(makeGroup(testDay: 5), members, checkIns, excuses: excuses, votes: votes)

        // Kept, kept, excused, kept, kept and kept today: the excuse pauses the run.
        let me: MemberStanding? = standing(s, "me")
        XCTAssertEqual(me?.history ?? [], [DayOutcome.kept, DayOutcome.kept, DayOutcome.excused, DayOutcome.kept,
                                           DayOutcome.kept])
        XCTAssertEqual(me?.streak, 5)
        XCTAssertEqual(me?.bestStreak, 5)

        // An excuse after a miss doesn't bridge it; being excused yesterday isn't a miss.
        let theo: MemberStanding? = standing(s, "theo")
        XCTAssertEqual(theo?.history ?? [], [DayOutcome.kept, DayOutcome.missed, DayOutcome.excused, DayOutcome.kept,
                                             DayOutcome.excused])
        XCTAssertEqual(theo?.streak, 1)
        XCTAssertEqual(theo?.bestStreak, 1)
        XCTAssertEqual(theo?.missedYesterday, false)

        // Yesterday's check-in was overruled: a miss.
        let maya: MemberStanding? = standing(s, "maya")
        XCTAssertEqual(maya?.streak, 0)
        XCTAssertEqual(maya?.bestStreak, 4)
        XCTAssertEqual(maya?.missedYesterday, true)
    }

    func testTodayOverruledAndExcusedToday() {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya"), member("theo", "Theo")]
        let checkIns: [CheckInInfo] = [checkIn("maya", 0), checkIn("maya", 1)]
        let excuses: [ExcuseInfo] = [excuse("me", 1), excuse("theo", 1)]
        let votes: [VoteInfo] = [against("me", "maya", 1), against("theo", "maya", 1),
                                 against("maya", "me", 1), against("theo", "me", 1)]
        let s: GroupSummary = summarize(makeGroup(testDay: 1), members, checkIns, excuses: excuses, votes: votes)

        let maya: MemberStanding? = standing(s, "maya")
        XCTAssertEqual(maya?.checkedInToday, true)
        XCTAssertEqual(maya?.excusedToday, false)
        XCTAssertEqual(maya?.todayOverruled, true)
        XCTAssertEqual(maya?.streak, 1)

        let me: MemberStanding? = standing(s, "me")
        XCTAssertEqual(me?.checkedInToday, false)
        XCTAssertEqual(me?.excusedToday, true)
        XCTAssertEqual(me?.todayOverruled, true)
        XCTAssertFalse(Digest.isOpen(s))

        let theo: MemberStanding? = standing(s, "theo")
        XCTAssertEqual(theo?.excusedToday, true)
        XCTAssertEqual(theo?.todayOverruled, false)
        XCTAssertFalse(s.standings.contains(where: { (m: MemberStanding) -> Bool in Digest.checkInStands(m) }))

        // Only day 0 has settled (you and Theo missed it); one vote fewer lets Maya's check-in stand again.
        XCTAssertEqual(s.totalForfeited, 4, accuracy: 1e-9)
        let fewer: GroupSummary = summarize(makeGroup(testDay: 1), members, checkIns, excuses: excuses,
                                            votes: [against("me", "maya", 1)])
        XCTAssertEqual(standing(fewer, "maya")?.todayOverruled, false)
        XCTAssertEqual(standing(fewer, "maya")?.streak, 2)
        XCTAssertEqual(fewer.standings.filter({ (m: MemberStanding) -> Bool in Digest.checkInStands(m) }).count, 1)
    }

    // MARK: - Ledger days

    func testOneForfeitSplitsAmongTwoKeepers() throws {
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya"), member("theo", "Theo")]
        let s: GroupSummary = summarize(makeGroup(testDay: 1, stake: 5), members, [checkIn("me", 0), checkIn("maya", 0)])
        let d: LedgerDay = try entry(s, 0)
        XCTAssertEqual(d.kept, [ari, maya])
        XCTAssertEqual(d.forfeits, [forfeit(theo, amount: 5)])
        XCTAssertEqual(d.share, 2.5, accuracy: 1e-9)

        // Activity draws one line per keeper from the forfeit: 5 / 2 each, which is the whole share.
        let each: Double = d.forfeits[0].amount / Double(d.kept.count)
        XCTAssertEqual(each, 2.5, accuracy: 1e-9)
        XCTAssertEqual(each, d.share, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 2.5, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, 2.5, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "theo")?.net ?? 99, -5, accuracy: 1e-9)
        XCTAssertEqual(Digest.viewerChange(s.days, day: 0, viewerID: "maya"), 2.5, accuracy: 1e-9)
        XCTAssertEqual(Digest.viewerChange(s.days, day: 0, viewerID: "theo"), -5, accuracy: 1e-9)
    }

    func testACarryAcrossANobodyKeptDayIsPaidOut() throws {
        // Day 0: nobody keeps, so 6 pts carry. Day 1: you and Maya keep and Theo misses. Day 2: all keep.
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya"), member("theo", "Theo")]
        let checkIns: [CheckInInfo] = [checkIn("me", 1), checkIn("maya", 1), checkIn("me", 2), checkIn("maya", 2),
                                       checkIn("theo", 2)]
        let s: GroupSummary = summarize(makeGroup(testDay: 3), members, checkIns)

        let nobody: LedgerDay = try entry(s, 0)
        XCTAssertEqual(nobody.kept, [])
        XCTAssertEqual(nobody.forfeits, [forfeit(ari), forfeit(maya), forfeit(theo)])
        XCTAssertEqual(nobody.share, 0, accuracy: 1e-9)
        XCTAssertEqual(nobody.carriedOut, 6, accuracy: 1e-9)

        let paid: LedgerDay = try entry(s, 1)
        XCTAssertEqual(paid.kept, [ari, maya])
        XCTAssertEqual(paid.carriedIn, 6, accuracy: 1e-9)
        XCTAssertEqual(paid.share, 4, accuracy: 1e-9)
        XCTAssertEqual(paid.carriedOut, 0, accuracy: 1e-9)
        // Each keeper: 3 from the carry and 1 from Theo's forfeit.
        let fromCarry: Double = paid.carriedIn / Double(paid.kept.count)
        var fromForfeits: Double = 0
        for f in paid.forfeits {
            fromForfeits += f.amount / Double(paid.kept.count)
        }
        XCTAssertEqual(fromCarry, 3, accuracy: 1e-9)
        XCTAssertEqual(fromForfeits, 1, accuracy: 1e-9)
        XCTAssertEqual(fromCarry + fromForfeits, paid.share, accuracy: 1e-9)

        XCTAssertEqual(try entry(s, 2), closed(2, kept: [ari, maya, theo]))
        XCTAssertEqual(s.pot, 0, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "me")?.net ?? 99, 2, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "maya")?.net ?? 99, 2, accuracy: 1e-9)
        XCTAssertEqual(standing(s, "theo")?.net ?? 99, -4, accuracy: 1e-9)
        var sum: Double = 0
        for m in s.standings {
            sum += m.net
        }
        XCTAssertEqual(sum, -s.pot, accuracy: 1e-9)
    }

    func testForfeitsSayWhyTheStakeWasLost() throws {
        // Maya's check-in and Theo's excuse are overruled (two of three each); Zed has no claim.
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya"), member("theo", "Theo"),
                                     member("zed", "Zed")]
        let votes: [VoteInfo] = [against("me", "maya", 0), against("zed", "maya", 0),
                                 against("me", "theo", 0), against("maya", "theo", 0)]
        let s: GroupSummary = summarize(makeGroup(testDay: 1), members, [checkIn("me", 0), checkIn("maya", 0)],
                                        excuses: [excuse("theo", 0)], votes: votes)
        let d: LedgerDay = try entry(s, 0)
        XCTAssertEqual(d.forfeits, [forfeit(maya, .checkInOverruled), forfeit(theo, .excuseOverruled), forfeit(zed)])
        XCTAssertEqual(d.kept, [ari])
        XCTAssertEqual(d.excused, [])
        XCTAssertEqual(d.share, 6, accuracy: 1e-9)
    }

    func testTodayListsItsJoinsAndLeavesOnly() throws {
        // Today is day 2: Lou joins and Maya leaves. You and Lou have already checked in.
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya", leftDay: 2),
                                     member("lou", "Lou", joinedDay: 2)]
        let checkIns: [CheckInInfo] = [checkIn("me", 0), checkIn("me", 1), checkIn("me", 2), checkIn("lou", 2)]
        let s: GroupSummary = summarize(makeGroup(testDay: 2), members, checkIns)
        XCTAssertEqual(s.days.first, LedgerDay(day: 2, isClosed: false, joined: [lou], left: [maya], kept: [], excused: [],
                                               forfeits: [], carriedIn: 0, share: 0, carriedOut: 0))
        XCTAssertTrue(try entry(s, 1).isClosed)
        XCTAssertEqual(s.pot, 0, accuracy: 1e-9)

        // A day later it has closed: the same joins and leaves, now with its outcomes.
        let later: GroupSummary = summarize(makeGroup(testDay: 3), members, checkIns)
        XCTAssertEqual(try entry(later, 2), closed(2, joined: [lou], left: [maya], kept: [ari, lou]))
        XCTAssertNil(later.days.first(where: { (d: LedgerDay) -> Bool in d.day == 3 }))
    }

    func testTheLedgerListsTheLatestDays() {
        // A solo member misses 130 days in a row: every day settles, the ledger keeps the newest 120.
        let s: GroupSummary = summarize(makeGroup(testDay: 130), [member("me", "Ari")], [])
        XCTAssertEqual(s.days.count, Settlement.dayCap)
        XCTAssertEqual(s.days.first?.day, 129)
        XCTAssertEqual(s.days.last?.day, 10)
        XCTAssertEqual(s.totalForfeited, 260, accuracy: 1e-9)
        XCTAssertEqual(s.pot, 260, accuracy: 1e-9)
        XCTAssertEqual(s.days.first?.carriedOut ?? 0, 260, accuracy: 1e-9)
    }
}
