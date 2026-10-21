import XCTest
@testable import Vow

final class ChatTextTests: XCTestCase {
    private let en: Locale = Locale(identifier: "en_US")
    /// 2026-10-01 00:00 UTC: day 0 is Oct 1 in UTC.
    private let created: Date = Date(timeIntervalSince1970: 1_790_812_800)
    /// 2026-10-10 12:00 UTC: day 9.
    private let now: Date = Date(timeIntervalSince1970: 1_791_633_600)

    private func makeGroup(isTest: Bool = false) -> GroupInfo {
        return GroupInfo(id: GroupID(zoneName: "group-chat-text", ownerName: "owner"),
                         name: "Morning Run",
                         stake: 2,
                         createdAt: created,
                         timeZoneID: "UTC",
                         isTest: isTest,
                         testDay: 9,
                         epoch: 0,
                         ownerUserID: "me",
                         shareURL: nil)
    }

    /// Maya's check-in on `day`, with three voters (two needed to overrule) unless told otherwise.
    private func tally(day: Int = 9, voters: Int = 3, needed: Int = 2, counts: Int = 0, against: Int = 0,
                       isOpen: Bool = true) -> ClaimTally {
        return ClaimTally(subject: "maya", day: day, kind: .checkIn, claimedAt: now, voters: voters, needed: needed,
                          countsVotes: counts, againstVotes: against, overruled: needed > 0 && against >= needed,
                          isOpen: isOpen, votes: [:])
    }

    // MARK: - Status

    func testOpenWithCountsVotes() {
        XCTAssertEqual(ChatText.status(tally(counts: 2), today: 9, isTest: false),
                       "2 say it counts · Voting ends tomorrow night")
        XCTAssertEqual(ChatText.status(tally(counts: 1), today: 9, isTest: false),
                       "1 says it counts · Voting ends tomorrow night")
    }

    func testYesterdaysClaimClosesTonight() {
        XCTAssertEqual(ChatText.status(tally(day: 8, needed: 3, against: 1), today: 9, isTest: false),
                       "1 of 3 needed to overrule · Voting ends tonight")
    }

    func testAgainstVotesTakeTheLineOverCountsVotes() {
        XCTAssertEqual(ChatText.status(tally(counts: 2, against: 1), today: 9, isTest: false),
                       "1 of 2 needed to overrule · Voting ends tomorrow night")
    }

    func testOverruledWhileVotingIsOpen() {
        XCTAssertEqual(ChatText.status(tally(day: 8, against: 3), today: 9, isTest: false),
                       "3 said it doesn't count · Voting ends tonight")
    }

    func testOpenWithoutVotesSaysOnlyWhenItEnds() {
        XCTAssertEqual(ChatText.status(tally(), today: 9, isTest: false), "Voting ends tomorrow night")
    }

    func testClosed() {
        XCTAssertEqual(ChatText.status(tally(day: 7, against: 3, isOpen: false), today: 9, isTest: false),
                       "Closed · 3 said it doesn't count")
        XCTAssertEqual(ChatText.status(tally(day: 7, counts: 2, isOpen: false), today: 9, isTest: false),
                       "Closed · 2 said it counts")
        XCTAssertEqual(ChatText.status(tally(day: 7, counts: 1, isOpen: false), today: 9, isTest: false),
                       "Closed · 1 said it counts")
        XCTAssertEqual(ChatText.status(tally(day: 7, isOpen: false), today: 9, isTest: false), "Closed")
    }

    func testATestGroupNamesTheDayThatClosesVoting() {
        // Day index 3 is "Day 4"; voting closes when the day after next, "Day 6", begins.
        XCTAssertEqual(ChatText.status(tally(day: 3), today: 3, isTest: true), "Voting ends when Day 6 begins")
        XCTAssertEqual(ChatText.status(tally(day: 3, counts: 1), today: 4, isTest: true),
                       "1 says it counts · Voting ends when Day 6 begins")
    }

    func testASoloClaimHasNoStatus() {
        XCTAssertNil(ChatText.status(tally(voters: 0, needed: 0), today: 9, isTest: false))
    }

    func testStatusIsSpokenAsSentences() {
        XCTAssertEqual(ChatText.spoken("2 say it counts · Voting ends tomorrow night"),
                       "2 say it counts. Voting ends tomorrow night")
    }

    // MARK: - Cards

    func testTitles() {
        XCTAssertEqual(ChatText.title(name: "Maya", isMine: false, kind: .checkIn), "Maya checked in")
        XCTAssertEqual(ChatText.title(name: "Alex", isMine: true, kind: .checkIn), "You checked in")
        XCTAssertEqual(ChatText.title(name: "Leo", isMine: false, kind: .excuse("Flight at 6")), "Leo sent an excuse")
        XCTAssertEqual(ChatText.title(name: "Alex", isMine: true, kind: .excuse("Sick")), "You sent an excuse")
    }

    func testSpokenHeader() {
        XCTAssertEqual(ChatText.spokenHeader(title: "Maya checked in", time: "8:14 PM", vow: "Swim 40 lengths",
                                             overruled: false),
                       "Maya checked in, 8:14 PM, Swim 40 lengths")
        XCTAssertEqual(ChatText.spokenHeader(title: "Priya checked in", time: "11:48 PM", vow: "", overruled: true),
                       "Priya checked in, 11:48 PM, overruled")
    }

    func testVoteWords() {
        XCTAssertEqual(ChatText.vote(true), "Counts")
        XCTAssertEqual(ChatText.vote(false), "Doesn't count")
        XCTAssertEqual(ChatText.voteLocked, "Votes can't change in the last 30 minutes")
    }

    func testMessageValue() {
        XCTAssertEqual(ChatText.messageValue(time: "8:21 PM", sending: false, failed: false), "8:21 PM")
        XCTAssertEqual(ChatText.messageValue(time: "8:21 PM", sending: true, failed: false), "Sending")
        XCTAssertEqual(ChatText.messageValue(time: "8:21 PM", sending: false, failed: true), "Not sent")
    }

    // MARK: - Feed

    func testDayHeaders() {
        let group: GroupInfo = makeGroup()
        XCTAssertEqual(ChatText.header(day: 9, today: 9, group: group, now: now, locale: en), "Today")
        XCTAssertEqual(ChatText.header(day: 8, today: 9, group: group, now: now, locale: en), "Yesterday")
        XCTAssertEqual(ChatText.header(day: 3, today: 9, group: group, now: now, locale: en), "Oct 4")
        XCTAssertEqual(ChatText.header(day: 3, today: 9, group: makeGroup(isTest: true), now: now, locale: en), "Day 4")
    }

    func testPointers() {
        let group: GroupInfo = makeGroup()
        XCTAssertEqual(ChatText.pointer(name: "Maya", isMine: false, claimDay: 8, isExcuse: false, today: 9,
                                        group: group, now: now, locale: en),
                       "Maya added proof to yesterday's check-in")
        XCTAssertEqual(ChatText.pointer(name: "Alex", isMine: true, claimDay: 9, isExcuse: true, today: 9,
                                        group: group, now: now, locale: en),
                       "You added proof to today's excuse")
        XCTAssertEqual(ChatText.pointer(name: "Sam", isMine: false, claimDay: 3, isExcuse: false, today: 9,
                                        group: group, now: now, locale: en),
                       "Sam added proof to Oct 4's check-in")
        XCTAssertEqual(ChatText.pointer(name: "Sam", isMine: false, claimDay: 3, isExcuse: false, today: 4,
                                        group: makeGroup(isTest: true), now: now, locale: en),
                       "Sam added proof to Day 4's check-in")
    }

    func testEmptyBody() {
        XCTAssertEqual(ChatText.emptyBody(hasVoters: true),
                       "Check-ins, proof and excuses show up here. Each one counts unless the group overrules it by "
                       + "the end of the next day.")
        XCTAssertEqual(ChatText.emptyBody(hasVoters: false), "Check-ins, proof and excuses show up here.")
    }

    // MARK: - "+" card

    func testPlusHeaders() {
        XCTAssertEqual(ChatText.plusHeader(proofDay: 9, kind: .checkIn, today: 9, isFinished: false),
                       "Proof for today's check-in")
        XCTAssertEqual(ChatText.plusHeader(proofDay: 9, kind: .excuse("Sick"), today: 9, isFinished: false),
                       "Proof for today's excuse")
        XCTAssertEqual(ChatText.plusHeader(proofDay: 8, kind: .checkIn, today: 9, isFinished: false),
                       "Proof for yesterday's check-in")
        XCTAssertEqual(ChatText.plusHeader(proofDay: 8, kind: .excuse("Sick"), today: 9, isFinished: false),
                       "Proof for yesterday's excuse")
        XCTAssertEqual(ChatText.plusHeader(proofDay: nil, kind: nil, today: 9, isFinished: false),
                       "Add proof after you check in")
        XCTAssertEqual(ChatText.plusHeader(proofDay: nil, kind: nil, today: 9, isFinished: true), "This vow has ended")
    }

    func testAFinishedVowsLastDayTakesProofTheDayAfter() {
        XCTAssertEqual(ChatText.plusHeader(proofDay: 29, kind: .checkIn, today: 30, isFinished: true),
                       "Proof for yesterday's check-in")
    }

    func testExcuseNotes() {
        XCTAssertNil(ChatText.excuseNote(nil))
        XCTAssertEqual(ChatText.excuseNote(.checkedIn), "You've checked in today")
        XCTAssertEqual(ChatText.excuseNote(.excused), "You're excused today")
        XCTAssertEqual(ChatText.excuseNote(.finished), "This vow has ended")
        XCTAssertEqual(ChatText.excuseNote(.notMember), "Write your vow to join")
    }
}
