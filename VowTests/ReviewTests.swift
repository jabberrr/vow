import XCTest
@testable import Vow

final class ReviewTests: XCTestCase {

    // MARK: - Fixtures

    /// 2026-01-01T00:00:00Z = 2025-12-31 19:00 in New York: day 0 is Dec 31, day 1 Jan 1, day 2 Jan 2.
    /// Day 1 starts at 1_767_243_600, day 2 at 1_767_330_000, day 3 at 1_767_416_400 (midnight EST).
    private let created: Date = Date(timeIntervalSince1970: 1_767_225_600)
    private let ny: String = "America/New_York"
    /// 2027-01-15T08:00:00Z: any moment for test groups, which ignore the clock.
    private let anyNow: Date = Date(timeIntervalSince1970: 1_800_000_000)

    private func date(_ seconds: Double) -> Date {
        return Date(timeIntervalSince1970: seconds)
    }

    private func makeGroup(isTest: Bool = true, testDay: Int = 0, endDay: Int? = nil,
                           rules: [VoteRuleChange]? = nil) -> GroupInfo {
        return GroupInfo(id: GroupID(zoneName: "group-review", ownerName: "owner"),
                         name: "Review",
                         stake: 2,
                         createdAt: created,
                         timeZoneID: ny,
                         isTest: isTest,
                         testDay: testDay,
                         epoch: 0,
                         ownerUserID: "me",
                         shareURL: nil,
                         endDay: endDay,
                         voteRules: rules)
    }

    private func member(_ id: String, _ name: String, joinedDay: Int = 0, leftDay: Int? = nil) -> MemberInfo {
        return MemberInfo(userID: id, displayName: name, vow: "I will read", joinedDay: joinedDay, joinedEpoch: 0,
                          leftDay: leftDay)
    }

    private func checkIn(_ id: String, _ day: Int, at seconds: Double? = nil) -> CheckInInfo {
        var served: Date? = nil
        if let s: Double = seconds {
            served = date(s)
        }
        return CheckInInfo(userID: id, day: day, epoch: 0, serverDate: served)
    }

    private func excuse(_ id: String, _ day: Int, _ text: String = "Sick", at seconds: Double? = nil) -> ExcuseInfo {
        var served: Date? = nil
        if let s: Double = seconds {
            served = date(s)
        }
        return ExcuseInfo(userID: id, day: day, epoch: 0, text: text, serverDate: served)
    }

    /// `voter`'s vote on `subject`'s claim for `day`: "Doesn't count" unless `counts`. Cast that day and
    /// pending unless told otherwise.
    private func vote(_ voter: String, _ subject: String, _ day: Int, counts: Bool = false, castDay: Int? = nil,
                      epoch: Int = 0, at seconds: Double? = nil) -> VoteInfo {
        var served: Date? = nil
        if let s: Double = seconds {
            served = date(s)
        }
        return VoteInfo(voterID: voter, subjectID: subject, day: day, epoch: epoch, counts: counts,
                        castDay: castDay ?? day, serverDate: served)
    }

    private func snapshot(_ group: GroupInfo, _ members: [MemberInfo], checkIns: [CheckInInfo] = [],
                          excuses: [ExcuseInfo] = [], votes: [VoteInfo] = []) -> GroupSnapshot {
        return GroupSnapshot(group: group, members: members, checkIns: checkIns, fetchedAt: created,
                             excuses: excuses, votes: votes)
    }

    private func history(_ snap: GroupSnapshot, _ id: String, now: Date? = nil) -> [DayOutcome] {
        let summary: GroupSummary = Settlement.summarize(snap, viewerID: "me", now: now ?? anyNow)
        for s in summary.standings where s.userID == id {
            return s.history
        }
        return []
    }

    private let trio: [MemberInfo] = [
        MemberInfo(userID: "me", displayName: "Ari", vow: "I will read", joinedDay: 0, joinedEpoch: 0, leftDay: nil),
        MemberInfo(userID: "maya", displayName: "Maya", vow: "I will run", joinedDay: 0, joinedEpoch: 0, leftDay: nil),
        MemberInfo(userID: "theo", displayName: "Theo", vow: "I will write", joinedDay: 0, joinedEpoch: 0, leftDay: nil)
    ]

    // MARK: - Thresholds

    func testNeededPerRule() {
        let expected: [VoteRule: [Int]] = [
            .majority: [1, 2, 2, 3, 3],
            .twoThirds: [1, 2, 2, 3, 4],
            .everyone: [1, 2, 3, 4, 5]
        ]
        for rule in VoteRule.allCases {
            for n in 1...5 {
                XCTAssertEqual(rule.needed(voters: n), expected[rule]?[n - 1], "\(rule) n=\(n)")
            }
        }
    }

    func testOverruleThresholdsForZeroToFiveVoters() throws {
        // Index n = 0...5 eligible voters; with none, nothing can be overruled.
        let needed: [VoteRule: [Int]] = [
            .majority: [0, 1, 2, 2, 3, 3],
            .twoThirds: [0, 1, 2, 2, 3, 4],
            .everyone: [0, 1, 2, 3, 4, 5]
        ]
        for rule in VoteRule.allCases {
            let group: GroupInfo = makeGroup(testDay: 1, rules: [VoteRuleChange(fromDay: 0, rule: rule)])
            for n in 0...5 {
                var members: [MemberInfo] = [member("maya", "Maya")]
                var voterIDs: [String] = []
                for i in 0..<n {
                    voterIDs.append("v\(i)")
                    members.append(member("v\(i)", "Voter \(i)"))
                }
                let need: Int = try XCTUnwrap(needed[rule]?[n])
                for againstCount in 0...n {
                    var votes: [VoteInfo] = []
                    for (i, id) in voterIDs.enumerated() {
                        votes.append(vote(id, "maya", 0, counts: i >= againstCount))
                    }
                    let overruled: Bool = n > 0 && againstCount >= need
                    let label: String = "\(rule) n=\(n) against=\(againstCount)"

                    let kept: GroupSnapshot = snapshot(group, members, checkIns: [checkIn("maya", 0)], votes: votes)
                    let tally: ClaimTally = try XCTUnwrap(Review.tally(subject: "maya", day: 0, snapshot: kept,
                                                                       now: anyNow), label)
                    XCTAssertEqual(tally.kind, .checkIn, label)
                    XCTAssertEqual(tally.voters, n, label)
                    XCTAssertEqual(tally.needed, need, label)
                    XCTAssertEqual(tally.againstVotes, againstCount, label)
                    XCTAssertEqual(tally.countsVotes, n - againstCount, label)
                    XCTAssertEqual(tally.overruled, overruled, label)
                    XCTAssertEqual(history(kept, "maya"), [overruled ? DayOutcome.missed : DayOutcome.kept], label)

                    let excused: GroupSnapshot = snapshot(group, members, excuses: [excuse("maya", 0)], votes: votes)
                    XCTAssertEqual(Review.tally(subject: "maya", day: 0, snapshot: excused, now: anyNow)?.overruled,
                                   overruled, label)
                    XCTAssertEqual(history(excused, "maya"), [overruled ? DayOutcome.missed : DayOutcome.excused],
                                   label)
                }
            }
        }
    }

    // MARK: - Window

    func testRealGroupWindowEdges() throws {
        let group: GroupInfo = makeGroup(isTest: false)
        let now: Date = date(1_767_459_600)                                // 2026-01-03 12:00 EST, day 3
        let claim: CheckInInfo = checkIn("maya", 0, at: 1_767_229_200)     // Dec 31 20:00, day 0
        let mine: VoteInfo = vote("me", "maya", 0, at: 1_767_240_000)      // Dec 31 23:00
        let edges: [(seconds: Double, inTime: Bool)] = [
            (seconds: 1_767_329_940, inTime: true),                         // Jan 1 23:59, day d + 1
            (seconds: 1_767_330_599, inTime: true),                         // Jan 2 00:09:59, grace into d + 2
            (seconds: 1_767_330_600, inTime: false)                         // Jan 2 00:10:00
        ]
        for edge in edges {
            let label: String = "\(edge.seconds)"
            let snap: GroupSnapshot = snapshot(group, trio, checkIns: [claim],
                                               votes: [mine, vote("theo", "maya", 0, castDay: 2, at: edge.seconds)])
            let tally: ClaimTally = try XCTUnwrap(Review.tally(subject: "maya", day: 0, snapshot: snap, now: now), label)
            XCTAssertEqual(tally.claimedAt, date(1_767_229_200), label)
            XCTAssertEqual(tally.againstVotes, edge.inTime ? 2 : 1, label)
            let theirs: Bool? = edge.inTime ? false : nil
            XCTAssertEqual(tally.votes["theo"], theirs, label)
            XCTAssertEqual(tally.overruled, edge.inTime, label)
            XCTAssertFalse(tally.isOpen, label)
            XCTAssertEqual(history(snap, "maya", now: now).first, edge.inTime ? DayOutcome.missed : DayOutcome.kept,
                           label)
        }
    }

    func testTestGroupsJudgeTheWindowByCastDay() {
        // Test groups ignore server dates (this one is in 2030); the voter's day stands in for them.
        let group: GroupInfo = makeGroup(testDay: 4)
        let mine: VoteInfo = vote("me", "maya", 1, castDay: 2, at: 1_900_000_000)
        let cases: [(theirs: VoteInfo, overruled: Bool)] = [
            (theirs: vote("theo", "maya", 1, castDay: 2, at: 1_900_000_000), overruled: true),
            (theirs: vote("theo", "maya", 1, castDay: 3, at: 1_900_000_000), overruled: false),
            (theirs: vote("theo", "maya", 1, castDay: 3), overruled: true)      // pending always counts
        ]
        for item in cases {
            let snap: GroupSnapshot = snapshot(group, trio, checkIns: [checkIn("maya", 1)], votes: [mine, item.theirs])
            XCTAssertEqual(Review.tally(subject: "maya", day: 1, snapshot: snap, now: anyNow)?.overruled, item.overruled,
                           "castDay \(item.theirs.castDay)")
            XCTAssertEqual(history(snap, "maya")[1], item.overruled ? DayOutcome.missed : DayOutcome.kept)
        }
    }

    func testIsOpenAndClosesAt() {
        let real: GroupInfo = makeGroup(isTest: false)
        let lastMinute: Date = date(1_767_329_940)                         // Jan 1 23:59 EST, day 1
        let nextDay: Date = date(1_767_330_030)                            // Jan 2 00:00:30 EST, day 2
        XCTAssertTrue(Review.isOpen(day: 0, group: real, now: lastMinute))
        XCTAssertTrue(Review.isOpen(day: 1, group: real, now: lastMinute))
        XCTAssertFalse(Review.isOpen(day: 2, group: real, now: lastMinute))
        XCTAssertFalse(Review.isOpen(day: 0, group: real, now: nextDay))
        XCTAssertTrue(Review.isOpen(day: 1, group: real, now: nextDay))
        XCTAssertEqual(Review.closesAt(day: 0, group: real), date(1_767_330_000))   // Jan 2 00:00 EST
        XCTAssertEqual(Review.closesAt(day: 1, group: real), date(1_767_416_400))   // Jan 3 00:00 EST

        let test: GroupInfo = makeGroup(testDay: 3)
        XCTAssertFalse(Review.isOpen(day: 1, group: test, now: anyNow))
        XCTAssertTrue(Review.isOpen(day: 2, group: test, now: anyNow))
        XCTAssertTrue(Review.isOpen(day: 3, group: test, now: anyNow))
        XCTAssertFalse(Review.isOpen(day: 4, group: test, now: anyNow))
        XCTAssertNil(Review.closesAt(day: 2, group: test))
    }

    func testAVoteStopsChangingHalfAnHourBeforeVotingCloses() {
        let real: GroupInfo = makeGroup(isTest: false)
        let before: Date = date(1_767_328_199)                             // Jan 1 23:29:59 EST, day 1
        let margin: Date = date(1_767_328_200)                             // Jan 1 23:30 EST
        XCTAssertTrue(Review.canChangeVote(day: 0, group: real, now: before))
        XCTAssertFalse(Review.canChangeVote(day: 0, group: real, now: margin))
        XCTAssertTrue(Review.isOpen(day: 0, group: real, now: margin))      // a first vote still goes in
        XCTAssertTrue(Review.canChangeVote(day: 1, group: real, now: margin))
        XCTAssertFalse(Review.canChangeVote(day: 0, group: real, now: date(1_767_330_030)))   // Jan 2 00:00:30 EST

        // A test group's votes are judged by the day they were cast, so a change counts until the day moves.
        let test: GroupInfo = makeGroup(testDay: 3)
        XCTAssertTrue(Review.canChangeVote(day: 2, group: test, now: anyNow))
        XCTAssertFalse(Review.canChangeVote(day: 1, group: test, now: anyNow))
    }

    func testTheFinalDayStaysOpenToVotesForADay() {
        // Final day 2; the clock is at day 3, so the vow is finished but day 2 can still be overruled.
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya")]
        let votes: [VoteInfo] = [vote("me", "maya", 2, castDay: 3, at: 1_900_000_000)]
        let finished: GroupInfo = makeGroup(testDay: 3, endDay: 2)
        XCTAssertTrue(Review.isOpen(day: 2, group: finished, now: anyNow))
        let snap: GroupSnapshot = snapshot(finished, members, checkIns: [checkIn("maya", 2)], votes: votes)
        XCTAssertEqual(history(snap, "maya"), [DayOutcome.missed, DayOutcome.missed, DayOutcome.missed])
        XCTAssertFalse(Review.isOpen(day: 2, group: makeGroup(testDay: 4, endDay: 2), now: anyNow))
    }

    // MARK: - Voters

    func testVoterEligibility() throws {
        // Theo leaves on day 1; Lou joins on day 2.
        let members: [MemberInfo] = [member("me", "Ari"), member("maya", "Maya"),
                                     member("theo", "Theo", leftDay: 1), member("lou", "Lou", joinedDay: 2)]
        let group: GroupInfo = makeGroup(testDay: 3)
        let checkIns: [CheckInInfo] = [checkIn("maya", 0), checkIn("maya", 2)]
        let base: GroupSnapshot = snapshot(group, members, checkIns: checkIns)
        XCTAssertEqual(Review.eligibleVoters(subject: "maya", day: 0, snapshot: base), ["me", "theo"])
        XCTAssertEqual(Review.eligibleVoters(subject: "maya", day: 2, snapshot: base), ["me", "lou"])
        XCTAssertEqual(Review.eligibleVoters(subject: "lou", day: 2, snapshot: base), ["me", "maya"])

        // Lou's vote on day 0 and Theo's on day 2 don't count; your own claim isn't yours to judge.
        let early: [VoteInfo] = [vote("lou", "maya", 0), vote("me", "maya", 0), vote("maya", "maya", 0)]
        let earlySnap: GroupSnapshot = snapshot(group, members, checkIns: checkIns, votes: early)
        let dayZero: ClaimTally = try XCTUnwrap(Review.tally(subject: "maya", day: 0, snapshot: earlySnap, now: anyNow))
        XCTAssertEqual(dayZero.voters, 2)
        XCTAssertEqual(dayZero.needed, 2)
        XCTAssertEqual(dayZero.votes, ["me": false])
        XCTAssertFalse(dayZero.overruled)
        let withTheo: GroupSnapshot = snapshot(group, members, checkIns: checkIns,
                                               votes: early + [vote("theo", "maya", 0)])
        XCTAssertEqual(Review.tally(subject: "maya", day: 0, snapshot: withTheo, now: anyNow)?.overruled, true)

        let late: [VoteInfo] = [vote("theo", "maya", 2), vote("me", "maya", 2)]
        let lateSnap: GroupSnapshot = snapshot(group, members, checkIns: checkIns, votes: late)
        XCTAssertEqual(Review.tally(subject: "maya", day: 2, snapshot: lateSnap, now: anyNow)?.againstVotes, 1)
        XCTAssertEqual(history(lateSnap, "maya")[2], DayOutcome.kept)
        let withLou: GroupSnapshot = snapshot(group, members, checkIns: checkIns, votes: late + [vote("lou", "maya", 2)])
        XCTAssertEqual(Review.tally(subject: "maya", day: 2, snapshot: withLou, now: anyNow)?.overruled, true)
        XCTAssertEqual(history(withLou, "maya")[2], DayOutcome.missed)
    }

    func testDuplicateVotesOtherEpochsAndSoloGroups() throws {
        let votes: [VoteInfo] = [vote("me", "maya", 0, counts: true), vote("me", "maya", 0),
                                 vote("theo", "maya", 0, epoch: 1)]
        let snap: GroupSnapshot = snapshot(makeGroup(testDay: 1), trio, checkIns: [checkIn("maya", 0)], votes: votes)
        let tally: ClaimTally = try XCTUnwrap(Review.tally(subject: "maya", day: 0, snapshot: snap, now: anyNow))
        XCTAssertEqual(tally.votes, ["me": true])
        XCTAssertEqual(tally.countsVotes, 1)
        XCTAssertEqual(tally.againstVotes, 0)

        // Alone, there is nobody to overrule you.
        let solo: GroupSnapshot = snapshot(makeGroup(testDay: 1), [member("me", "Ari")], excuses: [excuse("me", 0)])
        let mine: ClaimTally = try XCTUnwrap(Review.tally(subject: "me", day: 0, snapshot: solo, now: anyNow))
        XCTAssertEqual(mine.voters, 0)
        XCTAssertEqual(mine.needed, 0)
        XCTAssertFalse(mine.overruled)
        XCTAssertEqual(history(solo, "me"), [DayOutcome.excused])
    }

    // MARK: - Tally

    func testTally() throws {
        let group: GroupInfo = makeGroup(isTest: false)
        let now: Date = date(1_767_286_800)                                // 2026-01-01 12:00 EST, day 1
        let members: [MemberInfo] = trio + [member("lou", "Lou", leftDay: 0)]
        let snap: GroupSnapshot = snapshot(group, members,
                                           checkIns: [checkIn("maya", 0), checkIn("maya", 0, at: 1_767_229_200),
                                                      checkIn("lou", 0)],
                                           excuses: [excuse("theo", 1, "Flu")],
                                           votes: [vote("me", "maya", 0, counts: true, at: 1_767_240_000),
                                                   vote("theo", "maya", 0, castDay: 1, at: 1_767_276_000)])

        // Of a pending and a saved copy, the saved one dates the check-in.
        let dated: ClaimTally = try XCTUnwrap(Review.tally(subject: "maya", day: 0, snapshot: snap, now: now))
        XCTAssertEqual(dated, ClaimTally(subject: "maya", day: 0, kind: .checkIn, claimedAt: date(1_767_229_200),
                                           voters: 2, needed: 2, countsVotes: 1, againstVotes: 1, overruled: false,
                                           isOpen: true, votes: ["me": true, "theo": false]))

        let flu: ClaimTally = try XCTUnwrap(Review.tally(subject: "theo", day: 1, snapshot: snap, now: now))
        XCTAssertEqual(flu.kind, .excuse("Flu"))
        XCTAssertNil(flu.claimedAt)
        XCTAssertEqual(flu.voters, 2)
        XCTAssertTrue(flu.isOpen)

        XCTAssertNil(Review.tally(subject: "me", day: 0, snapshot: snap, now: now))     // no claim
        XCTAssertNil(Review.tally(subject: "maya", day: 1, snapshot: snap, now: now))
        XCTAssertNil(Review.tally(subject: "lou", day: 0, snapshot: snap, now: now))    // not taking part

        // A check-in and an excuse for one day (a race): the check-in is the claim.
        let both: GroupSnapshot = snapshot(group, trio, checkIns: [checkIn("maya", 1)], excuses: [excuse("maya", 1)])
        XCTAssertEqual(Review.tally(subject: "maya", day: 1, snapshot: both, now: now)?.kind, .checkIn)
    }

    /// A test group on day 6 with "Everyone" from day 3. Lou joins on day 2. Every day, each member checks
    /// in, sends an excuse or does neither, and everyone votes on everyone else.
    private func mixedSnapshot() -> GroupSnapshot {
        let members: [MemberInfo] = trio + [member("lou", "Lou", joinedDay: 2)]
        let ids: [String] = ["me", "maya", "theo", "lou"]
        let group: GroupInfo = makeGroup(testDay: 6, rules: [VoteRuleChange(fromDay: 3, rule: .everyone)])
        var checkIns: [CheckInInfo] = []
        var excuses: [ExcuseInfo] = []
        var votes: [VoteInfo] = []
        for day in 0...6 {
            for (i, id) in ids.enumerated() {
                switch (day + i) % 3 {
                case 0:
                    checkIns.append(checkIn(id, day))
                case 1:
                    excuses.append(excuse(id, day))
                default:
                    break
                }
                for (j, voter) in ids.enumerated() where voter != id {
                    votes.append(vote(voter, id, day, counts: (day + i + j) % 2 == 0))
                }
            }
        }
        return snapshot(group, members, checkIns: checkIns, excuses: excuses, votes: votes)
    }

    func testSettlementAndTallyAgree() throws {
        let snap: GroupSnapshot = mixedSnapshot()
        let summary: GroupSummary = Settlement.summarize(snap, viewerID: "me", now: anyNow)
        var overruled: Int = 0
        var stood: Int = 0
        for standing in summary.standings {
            let first: Int = standing.userID == "lou" ? 2 : 0
            for day in first..<6 {
                let outcome: DayOutcome = standing.history[day - first]
                guard let tally: ClaimTally = Review.tally(subject: standing.userID, day: day, snapshot: snap,
                                                           now: anyNow) else {
                    XCTAssertEqual(outcome, .missed, "\(standing.userID) day \(day)")
                    continue
                }
                let expected: DayOutcome = tally.overruled ? .missed : (tally.kind == .checkIn ? .kept : .excused)
                XCTAssertEqual(outcome, expected, "\(standing.userID) day \(day)")
                if tally.overruled {
                    overruled += 1
                } else {
                    stood += 1
                }
            }
            let today: ClaimTally? = Review.tally(subject: standing.userID, day: 6, snapshot: snap, now: anyNow)
            XCTAssertEqual(standing.todayOverruled, today?.overruled ?? false, "\(standing.userID) today")
        }
        XCTAssertGreaterThan(overruled, 0)
        XCTAssertGreaterThan(stood, 0)
    }

    func testTalliesMatchTallyForEveryClaim() {
        var mixed: GroupSnapshot = mixedSnapshot()
        mixed.checkIns.append(checkIn("me", 7))                            // a day the clock hasn't reached
        let all: [ClaimKey: ClaimTally] = Review.tallies(snapshot: mixed, now: anyNow)
        var expected: [ClaimKey: ClaimTally] = [:]
        for id in ["me", "maya", "theo", "lou"] {
            for day in 0...6 {
                if let tally: ClaimTally = Review.tally(subject: id, day: day, snapshot: mixed, now: anyNow) {
                    expected[ClaimKey(subject: id, day: day)] = tally
                }
            }
        }
        XCTAssertEqual(all, expected)
        XCTAssertGreaterThan(all.count, 10)
        XCTAssertNil(all[ClaimKey(subject: "me", day: 7)])
        XCTAssertNil(all[ClaimKey(subject: "lou", day: 1)])                // before Lou joined

        // A real group on day 1: a pending and a saved copy, a member who has left, and a race.
        let now: Date = date(1_767_286_800)                                // 2026-01-01 12:00 EST, day 1
        let members: [MemberInfo] = trio + [member("lou", "Lou", leftDay: 0)]
        let real: GroupSnapshot = snapshot(makeGroup(isTest: false), members,
                                           checkIns: [checkIn("maya", 0), checkIn("maya", 0, at: 1_767_229_200),
                                                      checkIn("lou", 0), checkIn("me", 1)],
                                           excuses: [excuse("theo", 1, "Flu"), excuse("me", 1)],
                                           votes: [vote("me", "maya", 0, counts: true, at: 1_767_240_000),
                                                   vote("theo", "maya", 0, castDay: 1, at: 1_767_276_000)])
        let tallies: [ClaimKey: ClaimTally] = Review.tallies(snapshot: real, now: now)
        XCTAssertEqual(Set(tallies.keys), [ClaimKey(subject: "maya", day: 0), ClaimKey(subject: "me", day: 1),
                                           ClaimKey(subject: "theo", day: 1)])
        for (key, tally) in tallies {
            XCTAssertEqual(tally, Review.tally(subject: key.subject, day: key.day, snapshot: real, now: now),
                           "\(key.subject) day \(key.day)")
        }
        XCTAssertEqual(tallies[ClaimKey(subject: "maya", day: 0)]?.claimedAt, date(1_767_229_200))
        XCTAssertEqual(tallies[ClaimKey(subject: "me", day: 1)]?.kind, .checkIn)
    }

    // MARK: - Proof day

    func testProofDayIsTodayElseYesterday() {
        let group: GroupInfo = makeGroup(testDay: 3)
        func proofDay(checkIns: [CheckInInfo] = [], excuses: [ExcuseInfo] = [], votes: [VoteInfo] = []) -> Int? {
            let snap: GroupSnapshot = snapshot(group, trio, checkIns: checkIns, excuses: excuses, votes: votes)
            return Review.proofDay(for: "me", snapshot: snap, now: anyNow)
        }
        XCTAssertNil(proofDay())
        XCTAssertEqual(proofDay(checkIns: [checkIn("me", 3)]), 3)
        XCTAssertEqual(proofDay(excuses: [excuse("me", 3)]), 3)
        XCTAssertEqual(proofDay(checkIns: [checkIn("me", 2), checkIn("me", 3)]), 3)
        XCTAssertEqual(proofDay(checkIns: [checkIn("me", 2)]), 2)
        XCTAssertEqual(proofDay(excuses: [excuse("me", 2)]), 2)
        XCTAssertNil(proofDay(checkIns: [checkIn("me", 1)]))               // voting on day 1 has closed
        XCTAssertNil(proofDay(checkIns: [checkIn("maya", 3)]))             // someone else's claim
        // An overruled claim still takes proof: it is how minds change while voting is open.
        XCTAssertEqual(proofDay(checkIns: [checkIn("me", 3)], votes: [vote("maya", "me", 3), vote("theo", "me", 3)]), 3)
    }

    func testProofDayNeedsYouToTakePart() {
        // Theo leaves on day 3; Lou joins on day 3.
        let members: [MemberInfo] = [member("me", "Ari"), member("theo", "Theo", leftDay: 3),
                                     member("lou", "Lou", joinedDay: 3)]
        let snap: GroupSnapshot = snapshot(makeGroup(testDay: 3), members,
                                           checkIns: [checkIn("theo", 2), checkIn("theo", 3), checkIn("lou", 2)])
        XCTAssertEqual(Review.proofDay(for: "theo", snapshot: snap, now: anyNow), 2)
        XCTAssertNil(Review.proofDay(for: "lou", snapshot: snap, now: anyNow))
        XCTAssertNil(Review.proofDay(for: "zed", snapshot: snap, now: anyNow))
    }

    func testProofDayInARealGroupFollowsTheClock() {
        let late: GroupSnapshot = snapshot(makeGroup(isTest: false), trio,
                                           checkIns: [checkIn("me", 1, at: 1_767_329_400)])   // Jan 1 23:50 EST
        XCTAssertEqual(Review.proofDay(for: "me", snapshot: late, now: date(1_767_329_700)), 1)  // Jan 1 23:55
        XCTAssertEqual(Review.proofDay(for: "me", snapshot: late, now: date(1_767_358_800)), 1)  // Jan 2 08:00
        XCTAssertNil(Review.proofDay(for: "me", snapshot: late, now: date(1_767_445_200)))      // Jan 3 08:00
        XCTAssertNil(Review.proofDay(for: "me", snapshot: snapshot(makeGroup(isTest: false), trio), now: created))
    }

    func testTheFinalDayTakesProofUntilTheDayAfter() {
        let checkIns: [CheckInInfo] = [checkIn("me", 2)]
        let dayAfter: GroupSnapshot = snapshot(makeGroup(testDay: 3, endDay: 2), trio, checkIns: checkIns)
        XCTAssertEqual(Review.proofDay(for: "me", snapshot: dayAfter, now: anyNow), 2)
        let later: GroupSnapshot = snapshot(makeGroup(testDay: 4, endDay: 2), trio, checkIns: checkIns)
        XCTAssertNil(Review.proofDay(for: "me", snapshot: later, now: anyNow))
    }

    // MARK: - Rule log

    func testRuleForDay() {
        let log: [VoteRuleChange] = [VoteRuleChange(fromDay: 3, rule: .twoThirds), VoteRuleChange(fromDay: 6, rule: .everyone)]
        let group: GroupInfo = makeGroup(rules: log)
        XCTAssertEqual(Review.rule(forDay: 0, group: group), .majority)
        XCTAssertEqual(Review.rule(forDay: 2, group: group), .majority)
        XCTAssertEqual(Review.rule(forDay: 3, group: group), .twoThirds)
        XCTAssertEqual(Review.rule(forDay: 5, group: group), .twoThirds)
        XCTAssertEqual(Review.rule(forDay: 6, group: group), .everyone)
        XCTAssertEqual(Review.rule(forDay: 100, group: group), .everyone)
        XCTAssertEqual(Review.rule(forDay: 4, group: makeGroup(rules: Array(log.reversed()))), .twoThirds)
        XCTAssertEqual(Review.rule(forDay: 4, group: makeGroup()), .majority)

        let tie: [VoteRuleChange] = [VoteRuleChange(fromDay: 3, rule: .twoThirds), VoteRuleChange(fromDay: 3, rule: .everyone)]
        XCTAssertEqual(Review.rule(forDay: 3, group: makeGroup(rules: tie)), .everyone)
    }

    func testChangingTakesEffectTomorrow() {
        let today: GroupInfo = makeGroup(testDay: 2)
        XCTAssertEqual(Review.changing(today, to: .majority, now: anyNow), [])
        XCTAssertEqual(Review.changing(today, to: .twoThirds, now: anyNow), [VoteRuleChange(fromDay: 3, rule: .twoThirds)])

        // Changing your mind the same day replaces tomorrow's change, or drops it.
        let planned: GroupInfo = makeGroup(testDay: 2, rules: [VoteRuleChange(fromDay: 3, rule: .twoThirds)])
        XCTAssertEqual(Review.changing(planned, to: .everyone, now: anyNow), [VoteRuleChange(fromDay: 3, rule: .everyone)])
        XCTAssertEqual(Review.changing(planned, to: .majority, now: anyNow), [])

        // Later on, the old change stays and the new one starts tomorrow.
        let later: GroupInfo = makeGroup(testDay: 5, rules: [VoteRuleChange(fromDay: 3, rule: .twoThirds)])
        XCTAssertEqual(Review.changing(later, to: .twoThirds, now: anyNow), [VoteRuleChange(fromDay: 3, rule: .twoThirds)])
        XCTAssertEqual(Review.changing(later, to: .majority, now: anyNow),
                       [VoteRuleChange(fromDay: 3, rule: .twoThirds), VoteRuleChange(fromDay: 6, rule: .majority)])

        // A real group follows the clock: 2026-01-02 12:00 EST is day 2.
        XCTAssertEqual(Review.changing(makeGroup(isTest: false), to: .everyone, now: date(1_767_373_200)),
                       [VoteRuleChange(fromDay: 3, rule: .everyone)])
    }

    func testRuleChangeIsNeverRetroactive() {
        // Maya has three voters: "More than half" takes 2 of them, "Everyone" all 3.
        let members: [MemberInfo] = trio + [member("lou", "Lou")]
        let checkIns: [CheckInInfo] = [checkIn("maya", 0), checkIn("maya", 1), checkIn("maya", 2), checkIn("maya", 3)]
        var votes: [VoteInfo] = []
        for day in 1...3 {
            votes.append(vote("me", "maya", day))
            votes.append(vote("theo", "maya", day))
        }
        // On day 2 the owner picks "Everyone".
        let log: [VoteRuleChange] = Review.changing(makeGroup(testDay: 2), to: .everyone, now: anyNow)
        XCTAssertEqual(log, [VoteRuleChange(fromDay: 3, rule: .everyone)])

        let before: GroupSummary = Settlement.summarize(snapshot(makeGroup(testDay: 3), members, checkIns: checkIns,
                                                                 votes: votes),
                                                        viewerID: "me", now: anyNow)
        let after: GroupSummary = Settlement.summarize(snapshot(makeGroup(testDay: 3, rules: log), members,
                                                                checkIns: checkIns, votes: votes),
                                                       viewerID: "me", now: anyNow)
        // Days 0...2, the day of the change included, settle exactly as before.
        XCTAssertEqual(after.ledger, before.ledger)
        XCTAssertEqual(after.totalForfeited, before.totalForfeited, accuracy: 1e-9)
        let maya: MemberStanding? = after.standings.first { (s: MemberStanding) -> Bool in s.userID == "maya" }
        XCTAssertEqual(maya?.history ?? [], [DayOutcome.kept, DayOutcome.missed, DayOutcome.missed])
        // From day 3, two of three no longer overrule.
        XCTAssertEqual(maya?.todayOverruled, false)
        let mayaBefore: MemberStanding? = before.standings.first { (s: MemberStanding) -> Bool in s.userID == "maya" }
        XCTAssertEqual(mayaBefore?.todayOverruled, true)

        let snap: GroupSnapshot = snapshot(makeGroup(testDay: 4, rules: log), members, checkIns: checkIns, votes: votes)
        XCTAssertEqual(Review.tally(subject: "maya", day: 2, snapshot: snap, now: anyNow)?.needed, 2)
        XCTAssertEqual(Review.tally(subject: "maya", day: 3, snapshot: snap, now: anyNow)?.needed, 3)
        XCTAssertEqual(history(snap, "maya"), [DayOutcome.kept, DayOutcome.missed, DayOutcome.missed, DayOutcome.kept])
    }

    func testRuleLogKeepsTheLatestChanges() {
        // A change every day for 70 days: changes from day 1 through day 70, of which the last 64 stay.
        var group: GroupInfo = makeGroup()
        for day in 0..<70 {
            group.testDay = day
            group.voteRules = Review.changing(group, to: day % 2 == 0 ? .twoThirds : .majority, now: anyNow)
        }
        let rules: [VoteRuleChange] = group.voteRules ?? []
        XCTAssertEqual(rules.count, Review.ruleLogCap)
        XCTAssertEqual(rules.first, VoteRuleChange(fromDay: 7, rule: .twoThirds))
        XCTAssertEqual(rules.last, VoteRuleChange(fromDay: 70, rule: .majority))
    }

    // MARK: - Persistence

    func testSnapshotCachedBeforeChatStillDecodes() throws {
        // What the previous build wrote for a snapshot (JSONEncoder: dates in seconds since 2001-01-01,
        // nil optionals left out): no excuses, votes, posts or voteRules.
        let json: String = """
        {
          "group": {
            "id": {"zoneName": "group-old", "ownerName": "owner"},
            "name": "Old",
            "stake": 2,
            "createdAt": 788918400,
            "timeZoneID": "America/New_York",
            "isTest": false,
            "testDay": 0,
            "epoch": 0,
            "ownerUserID": "me",
            "endDay": 29
          },
          "members": [
            {"userID": "me", "displayName": "Ari", "vow": "I will read", "joinedDay": 0, "joinedEpoch": 0}
          ],
          "checkIns": [
            {"userID": "me", "day": 0, "epoch": 0, "serverDate": 788925600}
          ],
          "fetchedAt": 788929200
        }
        """
        let old: GroupSnapshot = try JSONDecoder().decode(GroupSnapshot.self, from: Data(json.utf8))
        var group: GroupInfo = makeGroup(isTest: false, endDay: 29)
        group.id = GroupID(zoneName: "group-old", ownerName: "owner")
        group.name = "Old"
        let expected: GroupSnapshot = GroupSnapshot(group: group,
                                                    members: [member("me", "Ari")],
                                                    checkIns: [checkIn("me", 0, at: 1_767_232_800)],  // Dec 31 21:00
                                                    fetchedAt: date(1_767_236_400))
        XCTAssertEqual(old, expected)
        XCTAssertNil(old.group.voteRules)
        XCTAssertEqual(old.excuses, [])
        XCTAssertEqual(old.votes, [])
        XCTAssertEqual(old.posts, [])
    }

    func testSnapshotRoundTripsChat() throws {
        // Dates on Jan 1 in New York: 10:06 (excuse), 10:23 (vote), 12:53 (post).
        let post: PostInfo = PostInfo(id: "post-1", authorID: "maya", text: "Done", day: 1, epoch: 0, isProof: true,
                                      media: .video, aspect: 0.5625, duration: 12.5, serverDate: date(1_767_290_000))
        let snap: GroupSnapshot = snapshot(makeGroup(rules: [VoteRuleChange(fromDay: 3, rule: .twoThirds)]), trio,
                                           checkIns: [checkIn("maya", 1)],
                                           excuses: [excuse("me", 1, "Flu", at: 1_767_280_000)],
                                           votes: [vote("theo", "me", 1, counts: true, at: 1_767_281_000)])
        var withPost: GroupSnapshot = snap
        withPost.posts = [post]
        let data: Data = try JSONEncoder().encode(withPost)
        XCTAssertEqual(try JSONDecoder().decode(GroupSnapshot.self, from: data), withPost)
    }

    // MARK: - Activity

    func testActivityReadsReviewLines() throws {
        // You sit out, Maya's check-in is overruled (two of three), Theo keeps, Zed sits out too.
        let members: [MemberInfo] = trio + [member("zed", "Zed")]
        let snap: GroupSnapshot = snapshot(makeGroup(testDay: 1), members,
                                           checkIns: [checkIn("maya", 0), checkIn("theo", 0)],
                                           excuses: [excuse("me", 0), excuse("zed", 0)],
                                           votes: [vote("me", "maya", 0), vote("theo", "maya", 0)])
        let summary: GroupSummary = Settlement.summarize(snap, viewerID: "me", now: anyNow)
        let ranked: [LedgerLine] = LedgerFormat.ranked(summary.ledger)
        let bodies: [String] = ranked.map { (line: LedgerLine) -> String in LedgerFormat.body(line) }
        XCTAssertEqual(Array(bodies.prefix(4)), ["You were excused", "Pot split 1 way", "Maya's check-in was overruled",
                                                 "Zed was excused"])
        XCTAssertNil(LedgerFormat.trailing(ranked[0]))
        XCTAssertEqual(LedgerFormat.trailing(ranked[2]), "\u{2212}2 pts")
        XCTAssertEqual(LedgerFormat.symbol(.excused), "pause.circle")
        XCTAssertFalse(LedgerFormat.isOwn(.excused))

        let hers: GroupSummary = Settlement.summarize(snap, viewerID: "maya", now: anyNow)
        let own: LedgerLine = try XCTUnwrap(hers.ledger.first { (line: LedgerLine) -> Bool in line.kind == .missed })
        XCTAssertEqual(LedgerFormat.body(own), "Your check-in was overruled")
        XCTAssertEqual(LedgerFormat.trailing(own), "\u{2212}2 pts")
        XCTAssertEqual(LedgerFormat.spoken(own), "Your check-in was overruled, minus 2 points")

        let plain: LedgerLine = LedgerLine(id: "d0-missed-me", day: 0, kind: .missed,
                                           text: "Day 1 · You missed · \u{2212}2 pts", amount: -2)
        XCTAssertEqual(LedgerFormat.body(plain), "You missed")
    }
}
