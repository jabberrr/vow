import XCTest
@testable import Vow

final class ChatFeedTests: XCTestCase {

    // MARK: - Fixtures

    /// 2026-10-01 00:00 UTC: day 0 is Oct 1 in UTC, so day d starts at `created` + d × 86,400.
    private let created: Date = Date(timeIntervalSince1970: 1_790_812_800)
    /// 2026-10-10 12:00 UTC: day 9 (Oct 10). The seven days shown are days 3 through 9.
    private let now: Date = Date(timeIntervalSince1970: 1_791_633_600)

    /// `hour`:`minute` UTC on group day `day`.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        return created.addingTimeInterval(Double(day * 86_400 + hour * 3_600 + minute * 60))
    }

    private func makeGroup(isTest: Bool = false, testDay: Int = 0, epoch: Int = 0, endDay: Int? = nil) -> GroupInfo {
        return GroupInfo(id: GroupID(zoneName: "group-chat", ownerName: "owner"),
                         name: "Morning Run",
                         stake: 2,
                         createdAt: created,
                         timeZoneID: "UTC",
                         isTest: isTest,
                         testDay: testDay,
                         epoch: epoch,
                         ownerUserID: "me",
                         shareURL: nil,
                         endDay: endDay)
    }

    private func member(_ id: String, _ name: String, joinedDay: Int = 0) -> MemberInfo {
        return MemberInfo(userID: id, displayName: name, vow: "I will swim 40 lengths", joinedDay: joinedDay,
                          joinedEpoch: 0, leftDay: nil)
    }

    private var everyone: [MemberInfo] {
        return [member("me", "Alex"), member("maya", "Maya"), member("sam", "Sam")]
    }

    private func checkIn(_ id: String, _ day: Int, at served: Date?) -> CheckInInfo {
        return CheckInInfo(userID: id, day: day, epoch: 0, serverDate: served)
    }

    private func excuse(_ id: String, _ day: Int, at served: Date?) -> ExcuseInfo {
        return ExcuseInfo(userID: id, day: day, epoch: 0, text: "Sick", serverDate: served)
    }

    /// A pending "Doesn't count" unless `counts`.
    private func vote(_ voter: String, on subject: String, _ day: Int, counts: Bool = false) -> VoteInfo {
        return VoteInfo(voterID: voter, subjectID: subject, day: day, epoch: 0, counts: counts, castDay: day,
                        serverDate: nil)
    }

    private func message(_ id: String, by author: String, day: Int, at served: Date?, epoch: Int = 0) -> PostInfo {
        return PostInfo(id: id, authorID: author, text: "Hi", day: day, epoch: epoch, isProof: false, media: .none,
                        aspect: nil, duration: nil, serverDate: served)
    }

    private func proof(_ id: String, by author: String, day: Int, at served: Date?) -> PostInfo {
        return PostInfo(id: id, authorID: author, text: "", day: day, epoch: 0, isProof: true, media: .photo,
                        aspect: 1.5, duration: nil, serverDate: served)
    }

    /// A saved reaction; "" is one taken back.
    private func reaction(_ user: String, on postID: String, _ emoji: String) -> ReactionInfo {
        return ReactionInfo(userID: user, postID: postID, emoji: emoji, serverDate: at(9, 11))
    }

    private func feed(_ group: GroupInfo? = nil,
                      members: [MemberInfo]? = nil,
                      checkIns: [CheckInInfo] = [],
                      excuses: [ExcuseInfo] = [],
                      votes: [VoteInfo] = [],
                      posts: [PostInfo] = [],
                      reactions: [ReactionInfo] = [],
                      viewer: String = "me",
                      showAll: Bool = false,
                      now: Date? = nil) -> ChatFeed {
        let snapshot: GroupSnapshot = GroupSnapshot(group: group ?? makeGroup(), members: members ?? everyone,
                                                    checkIns: checkIns, fetchedAt: created, excuses: excuses,
                                                    votes: votes, posts: posts, reactions: reactions)
        return ChatFeed.build(snapshot, viewerID: viewer, now: now ?? self.now, showAll: showAll)
    }

    private func ids(_ feed: ChatFeed) -> [String] {
        return feed.rows.map { (row: ChatRow) -> String in row.id }
    }

    private func claim(_ feed: ChatFeed, _ id: String) -> ChatClaim? {
        for row in feed.rows where row.id == id {
            if case .claim(let claim) = row.content {
                return claim
            }
        }
        return nil
    }

    private func message(_ feed: ChatFeed, _ id: String) -> ChatMessage? {
        for row in feed.rows where row.id == id {
            if case .message(let message) = row.content {
                return message
            }
        }
        return nil
    }

    private func row(_ feed: ChatFeed, _ id: String) -> ChatRow? {
        return feed.rows.first { (row: ChatRow) -> Bool in row.id == id }
    }

    // MARK: - Order and sections

    func testItemsSortByDayThenTimeWithAHeaderPerDay() {
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 9, at: at(9, 9))],
                               posts: [message("m-late", by: "sam", day: 9, at: at(9, 9, 10)),
                                       message("m-early", by: "sam", day: 8, at: at(8, 20))])
        XCTAssertEqual(ids(f), ["day-8", "m-early", "day-9", "claim-9-maya", "m-late"])
    }

    func testARealGroupsMessageBelongsToTheDayTheServerTookIt() {
        // Sent from a device that still thought it was day 8; the server took it on day 9.
        let f: ChatFeed = feed(posts: [message("m1", by: "sam", day: 8, at: at(9, 0, 5))])
        XCTAssertEqual(ids(f), ["day-9", "m1"])
    }

    func testATestGroupsMessageKeepsTheDayItWasSentOn() {
        let group: GroupInfo = makeGroup(isTest: true, testDay: 3)
        let f: ChatFeed = feed(group, posts: [message("m1", by: "sam", day: 2, at: at(9, 9))])
        XCTAssertEqual(ids(f), ["day-2", "m1"])
    }

    func testSendingItemsComeLastInTheOrderSent() {
        // A served message the device's clock thinks is in the future still sorts before anything sending.
        let f: ChatFeed = feed(posts: [message("p-first", by: "me", day: 9, at: nil),
                                       message("m-served", by: "sam", day: 9, at: at(9, 11, 59)),
                                       message("m-ahead", by: "sam", day: 9, at: at(9, 12, 30)),
                                       message("p-second", by: "me", day: 9, at: nil)])
        XCTAssertEqual(ids(f), ["day-9", "m-served", "m-ahead", "p-first", "p-second"])
        XCTAssertEqual(message(f, "p-first")?.time, now)
    }

    func testAPendingCheckInIsAtTheEndOfToday() {
        let f: ChatFeed = feed(checkIns: [checkIn("me", 9, at: nil)],
                               posts: [message("m1", by: "sam", day: 9, at: at(9, 11))])
        XCTAssertEqual(ids(f), ["day-9", "m1", "claim-9-me"])
        XCTAssertEqual(f.rows.last?.isOwnPending, true)
    }

    func testGapsAroundHeadersItemsAndRuns() {
        let f: ChatFeed = feed(posts: [message("a", by: "sam", day: 9, at: at(9, 10)),
                                       message("b", by: "sam", day: 9, at: at(9, 10, 2)),
                                       message("c", by: "maya", day: 9, at: at(9, 10, 3))])
        XCTAssertEqual(row(f, "day-9")?.gap, .section)
        XCTAssertEqual(row(f, "a")?.gap, ChatGap.none)
        XCTAssertEqual(row(f, "b")?.gap, .run)
        XCTAssertEqual(row(f, "c")?.gap, .item)
    }

    // MARK: - Range

    func testTheLastSevenDaysShowAndOlderItemsWaitBehindEarlier() {
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 1, at: at(1, 9))],
                               posts: [message("old", by: "sam", day: 2, at: at(2, 9)),
                                       message("first", by: "sam", day: 3, at: at(3, 9)),
                                       message("latest", by: "sam", day: 9, at: at(9, 9))])
        XCTAssertTrue(f.hasEarlier)
        XCTAssertEqual(ids(f), ["day-3", "first", "day-9", "latest"])
    }

    func testEarlierShowsTheWholeEpoch() {
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 1, at: at(1, 9))],
                               posts: [message("old", by: "sam", day: 2, at: at(2, 9)),
                                       message("first", by: "sam", day: 3, at: at(3, 9))],
                               showAll: true)
        XCTAssertFalse(f.hasEarlier)
        XCTAssertEqual(ids(f), ["day-1", "claim-1-maya", "day-2", "old", "day-3", "first"])
    }

    func testNoEarlierWhenNothingIsOlder() {
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 3, at: at(3, 9))])
        XCTAssertFalse(f.hasEarlier)
        XCTAssertFalse(f.isEmpty)
    }

    func testAQuietChatOpensOnTheLastWeekAnythingHappened() {
        // Day 20, and nothing since day 12: the week shown is days 6 through 12.
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 12, at: at(12, 9))],
                               posts: [message("old", by: "sam", day: 2, at: at(2, 9)),
                                       message("quiet", by: "sam", day: 10, at: at(10, 9))],
                               now: at(20, 12))
        XCTAssertTrue(f.hasEarlier)
        XCTAssertEqual(ids(f), ["day-10", "quiet", "day-12", "claim-12-maya"])
    }

    func testAFinishedVowOpensOnItsLastWeekWithoutTheRule() {
        // The vow ended on day 9; the clock is at day 20.
        let f: ChatFeed = feed(makeGroup(endDay: 9),
                               checkIns: [checkIn("maya", 9, at: at(9, 9)), checkIn("sam", 3, at: at(3, 9))],
                               posts: [message("old", by: "sam", day: 1, at: at(1, 9))],
                               now: at(20, 12))
        XCTAssertTrue(f.hasEarlier)
        XCTAssertEqual(ids(f), ["day-3", "claim-3-sam", "day-9", "claim-9-maya"])
        XCTAssertFalse(f.hasVoters)
    }

    func testOtherEpochsAreLeftOut() {
        let f: ChatFeed = feed(makeGroup(epoch: 1), posts: [message("m1", by: "sam", day: 9, at: at(9, 9), epoch: 0)])
        XCTAssertTrue(f.isEmpty)
    }

    func testNothingYetIsEmpty() {
        let f: ChatFeed = feed()
        XCTAssertTrue(f.isEmpty)
        XCTAssertTrue(f.rows.isEmpty)
    }

    // MARK: - Proof and pointers

    func testProofSitsInsideItsCardOnly() {
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 9, at: at(9, 9))],
                               posts: [proof("p2", by: "maya", day: 9, at: at(9, 9, 6)),
                                       proof("p1", by: "maya", day: 9, at: at(9, 9, 5))])
        XCTAssertEqual(ids(f), ["day-9", "claim-9-maya"])
        XCTAssertEqual(claim(f, "claim-9-maya")?.proofs.map { (p: PostInfo) -> String in p.id }, ["p1", "p2"])
    }

    func testAPointerFollowsWhenSomethingCameBetween() {
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 9, at: at(9, 9))],
                               posts: [message("s1", by: "sam", day: 9, at: at(9, 9, 2)),
                                       proof("p1", by: "maya", day: 9, at: at(9, 9, 5))])
        XCTAssertEqual(ids(f), ["day-9", "claim-9-maya", "s1", "pointer-p1"])
        XCTAssertEqual(claim(f, "claim-9-maya")?.proofs.count, 1)
        guard case .pointer(let pointer)? = row(f, "pointer-p1")?.content else {
            return XCTFail("No pointer")
        }
        XCTAssertEqual(pointer.cardID, "claim-9-maya")
        XCTAssertEqual(pointer.author, "Maya")
        XCTAssertFalse(pointer.isExcuse)
    }

    func testAPointerSitsOnTheDayTheProofArrived() {
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 8, at: at(8, 23, 50))],
                               posts: [message("s1", by: "sam", day: 8, at: at(8, 23, 55)),
                                       proof("p1", by: "maya", day: 8, at: at(9, 7))])
        XCTAssertEqual(ids(f), ["day-8", "claim-8-maya", "s1", "day-9", "pointer-p1"])
        guard case .pointer(let pointer)? = row(f, "pointer-p1")?.content else {
            return XCTFail("No pointer")
        }
        XCTAssertEqual(pointer.claimDay, 8)
    }

    func testAnotherCardBetweenAlsoCallsForAPointer() {
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 9, at: at(9, 9)), checkIn("sam", 9, at: at(9, 9, 1))],
                               posts: [proof("p1", by: "maya", day: 9, at: at(9, 9, 5))])
        XCTAssertEqual(ids(f), ["day-9", "claim-9-maya", "claim-9-sam", "pointer-p1"])
    }

    func testNoPointerWhenTheCardIsLast() {
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 9, at: at(9, 9))],
                               posts: [message("s0", by: "sam", day: 9, at: at(9, 8)),
                                       proof("p1", by: "maya", day: 9, at: at(9, 9, 5))])
        XCTAssertEqual(ids(f), ["day-9", "s0", "claim-9-maya"])
    }

    func testTestGroupsHaveNoPointers() {
        let group: GroupInfo = makeGroup(isTest: true, testDay: 9)
        let f: ChatFeed = feed(group,
                               checkIns: [checkIn("maya", 9, at: at(9, 9))],
                               posts: [message("s1", by: "sam", day: 9, at: at(9, 9, 2)),
                                       proof("p1", by: "maya", day: 9, at: at(9, 9, 5))])
        XCTAssertEqual(ids(f), ["day-9", "claim-9-maya", "s1"])
        XCTAssertEqual(claim(f, "claim-9-maya")?.proofs.count, 1)
    }

    func testYourSendingProofsPointerIsYoursAndPending() {
        let f: ChatFeed = feed(checkIns: [checkIn("me", 9, at: at(9, 9))],
                               posts: [message("s1", by: "sam", day: 9, at: at(9, 9, 2)),
                                       proof("p1", by: "me", day: 9, at: nil)])
        XCTAssertEqual(f.rows.last?.id, "pointer-p1")
        XCTAssertEqual(f.rows.last?.isOwnPending, true)
    }

    // MARK: - Runs

    func testMessagesWithinFiveMinutesFormARun() {
        let f: ChatFeed = feed(posts: [message("a", by: "maya", day: 9, at: at(9, 10)),
                                       message("b", by: "maya", day: 9, at: at(9, 10, 4)),
                                       message("c", by: "maya", day: 9, at: at(9, 10, 10)),
                                       message("d", by: "sam", day: 9, at: at(9, 10, 11))])
        XCTAssertEqual(message(f, "a")?.startsRun, true)
        XCTAssertEqual(message(f, "a")?.endsRun, false)
        XCTAssertEqual(message(f, "b")?.startsRun, false)
        XCTAssertEqual(message(f, "b")?.endsRun, true)
        XCTAssertEqual(message(f, "c")?.startsRun, true)
        XCTAssertEqual(message(f, "c")?.endsRun, true)
        XCTAssertEqual(message(f, "d")?.startsRun, true)
    }

    func testACardBreaksARun() {
        let f: ChatFeed = feed(checkIns: [checkIn("sam", 9, at: at(9, 10, 1))],
                               posts: [message("a", by: "maya", day: 9, at: at(9, 10)),
                                       message("b", by: "maya", day: 9, at: at(9, 10, 2))])
        XCTAssertEqual(message(f, "a")?.endsRun, true)
        XCTAssertEqual(message(f, "b")?.startsRun, true)
    }

    func testANewDayBreaksARun() {
        let f: ChatFeed = feed(posts: [message("a", by: "maya", day: 8, at: at(8, 23, 59)),
                                       message("b", by: "maya", day: 9, at: at(9, 0, 1))])
        XCTAssertEqual(message(f, "a")?.endsRun, true)
        XCTAssertEqual(message(f, "b")?.startsRun, true)
    }

    // MARK: - Cards

    func testCompactUntilProofOrAVote() {
        let tally: ClaimTally = ClaimTally(subject: "maya", day: 9, kind: .checkIn, claimedAt: at(9, 9), voters: 2,
                                           needed: 2, countsVotes: 0, againstVotes: 0, overruled: false,
                                           isOpen: true, votes: [:])
        XCTAssertTrue(ChatFeed.isCompact(tally, proofCount: 0))
        XCTAssertFalse(ChatFeed.isCompact(tally, proofCount: 1))
        let voted: ClaimTally = ClaimTally(subject: "maya", day: 9, kind: .checkIn, claimedAt: at(9, 9), voters: 2,
                                           needed: 2, countsVotes: 1, againstVotes: 0, overruled: false,
                                           isOpen: true, votes: ["sam": true])
        XCTAssertFalse(ChatFeed.isCompact(voted, proofCount: 0))
        let excused: ClaimTally = ClaimTally(subject: "maya", day: 9, kind: .excuse("Sick"), claimedAt: at(9, 9),
                                             voters: 2, needed: 2, countsVotes: 0, againstVotes: 0, overruled: false,
                                             isOpen: true, votes: [:])
        XCTAssertFalse(ChatFeed.isCompact(excused, proofCount: 0))
    }

    func testYourPendingVoteOpensTheCard() {
        let before: ChatFeed = feed(checkIns: [checkIn("maya", 9, at: at(9, 9))])
        XCTAssertEqual(claim(before, "claim-9-maya")?.isCompact, true)
        let after: ChatFeed = feed(checkIns: [checkIn("maya", 9, at: at(9, 9))],
                                   votes: [vote("me", on: "maya", 9, counts: true)])
        XCTAssertEqual(claim(after, "claim-9-maya")?.isCompact, false)
        XCTAssertEqual(claim(after, "claim-9-maya")?.myVote, true)
    }

    func testSendingAndFailedProofOpenTheCard() {
        let f: ChatFeed = feed(checkIns: [checkIn("me", 9, at: at(9, 9))],
                               posts: [proof("p1", by: "me", day: 9, at: nil)])
        XCTAssertEqual(claim(f, "claim-9-me")?.isCompact, false)
    }

    func testAnExcuseCardIsNeverCompact() {
        let f: ChatFeed = feed(excuses: [excuse("maya", 9, at: at(9, 8))])
        XCTAssertEqual(claim(f, "claim-9-maya")?.isCompact, false)
        XCTAssertEqual(claim(f, "claim-9-maya")?.tally.kind, .excuse("Sick"))
    }

    func testYouVoteOnlyOnOthersOpenClaimsOnDaysYouTakePart() {
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 9, at: at(9, 9)),
                                          checkIn("me", 9, at: at(9, 9)),
                                          checkIn("sam", 7, at: at(7, 9))])
        XCTAssertEqual(claim(f, "claim-9-maya")?.canVote, true)
        XCTAssertEqual(claim(f, "claim-9-me")?.canVote, false)
        XCTAssertEqual(claim(f, "claim-9-me")?.canChangeVote, false)
        XCTAssertEqual(claim(f, "claim-7-sam")?.canVote, false)

        let joinedToday: [MemberInfo] = [member("me", "Alex", joinedDay: 9), member("maya", "Maya")]
        let late: ChatFeed = feed(members: joinedToday, checkIns: [checkIn("maya", 8, at: at(8, 9))])
        XCTAssertEqual(claim(late, "claim-8-maya")?.canVote, false)
    }

    func testYourVoteStopsChangingInVotingsLastHalfHour() {
        // 23:45 on day 9: voting on day 8 closes at midnight, on day 9 a day later.
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 8, at: at(8, 9)), checkIn("sam", 9, at: at(9, 9))],
                               now: at(9, 23, 45))
        XCTAssertEqual(claim(f, "claim-8-maya")?.canVote, true)
        XCTAssertEqual(claim(f, "claim-8-maya")?.canChangeVote, false)
        XCTAssertEqual(claim(f, "claim-9-sam")?.canChangeVote, true)
    }

    func testWhoVotedListsYouFirstThenInMemberOrder() {
        let members: [MemberInfo] = everyone + [member("ann", "Ann")]
        let f: ChatFeed = feed(members: members,
                               checkIns: [checkIn("maya", 9, at: at(9, 9))],
                               votes: [vote("sam", on: "maya", 9, counts: true),
                                       vote("me", on: "maya", 9),
                                       vote("ann", on: "maya", 9, counts: true)])
        let voters: [ChatVoter] = claim(f, "claim-9-maya")?.voters ?? []
        XCTAssertEqual(voters.map { (v: ChatVoter) -> String in v.id }, ["me", "ann", "sam"])
        XCTAssertEqual(voters.map { (v: ChatVoter) -> String in v.name }, ["You", "Ann", "Sam"])
        XCTAssertEqual(voters.map { (v: ChatVoter) -> Bool in v.counts }, [false, true, true])
    }

    func testNamesAndVowsComeFromTheMemberRecords() {
        let members: [MemberInfo] = [member("me", "Alex"), member("maya", "  ")]
        let f: ChatFeed = feed(members: members, checkIns: [checkIn("maya", 9, at: at(9, 9))])
        let card: ChatClaim? = claim(f, "claim-9-maya")
        XCTAssertEqual(card?.name, "Someone")
        XCTAssertEqual(card?.vow, "Swim 40 lengths")
        XCTAssertEqual(card?.isMine, false)
    }

    // MARK: - Reactions

    func testAMessageCarriesItsReactionsInChoiceOrder() {
        let f: ChatFeed = feed(posts: [message("m1", by: "sam", day: 9, at: at(9, 10)),
                                       message("m2", by: "maya", day: 9, at: at(9, 10, 30))],
                               reactions: [reaction("maya", on: "m1", "😂"),
                                           reaction("me", on: "m1", "❤️"),
                                           reaction("sam", on: "m1", "😂")])
        let chips: [ReactionCount] = message(f, "m1")?.reactions ?? []
        XCTAssertEqual(chips.map { (c: ReactionCount) -> String in c.emoji }, ["❤️", "😂"])
        XCTAssertEqual(chips.map { (c: ReactionCount) -> Int in c.count }, [1, 2])
        XCTAssertEqual(chips.map { (c: ReactionCount) -> Bool in c.mine }, [true, false])
        XCTAssertEqual(message(f, "m1")?.myReaction, "❤️")
        XCTAssertEqual(message(f, "m2")?.reactions, [])
        XCTAssertNil(message(f, "m2")?.myReaction)
    }

    func testTheFeedsReactionsAreTheDomainsCounts() {
        let posts: [PostInfo] = [message("m1", by: "sam", day: 9, at: at(9, 10))]
        let reactions: [ReactionInfo] = [reaction("maya", on: "m1", "🔥"), reaction("me", on: "m1", "🔥"),
                                         reaction("me", on: "m1", "👍")]
        let snapshot: GroupSnapshot = GroupSnapshot(group: makeGroup(), members: everyone, checkIns: [],
                                                    fetchedAt: created, posts: posts, reactions: reactions)
        let built: ChatFeed = ChatFeed.build(snapshot, viewerID: "me", now: now, showAll: false)
        XCTAssertEqual(message(built, "m1")?.reactions, Reactions.counts(in: snapshot, viewerID: "me")["m1"])
        XCTAssertEqual(message(built, "m1")?.myReaction, "👍")
    }

    func testAReactionTakenBackLeavesNoChip() {
        let f: ChatFeed = feed(posts: [message("m1", by: "sam", day: 9, at: at(9, 10))],
                               reactions: [reaction("me", on: "m1", "❤️"), reaction("me", on: "m1", "")])
        XCTAssertEqual(message(f, "m1")?.reactions, [])
        XCTAssertEqual(f.shape.reactionChips, 0)
    }

    func testChipsOnShownMessagesShapeTheFeed() {
        let f: ChatFeed = feed(posts: [message("old", by: "sam", day: 1, at: at(1, 9)),
                                       message("m1", by: "sam", day: 9, at: at(9, 10)),
                                       message("m2", by: "maya", day: 9, at: at(9, 11))],
                               reactions: [reaction("me", on: "m1", "❤️"), reaction("maya", on: "m1", "😮"),
                                           reaction("sam", on: "m2", "👏"), reaction("me", on: "old", "🔥")])
        // "old" is behind Earlier, so its chip doesn't count.
        XCTAssertEqual(f.shape.reactionChips, 3)
    }

    func testTheReactionPickerFindsItsMessage() {
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 9, at: at(9, 9))],
                               posts: [message("m1", by: "sam", day: 9, at: at(9, 10))])
        XCTAssertEqual(f.message("m1")?.post.id, "m1")
        XCTAssertNil(f.message("claim-9-maya"))
        XCTAssertNil(f.message("gone"))
    }

    // MARK: - The "+" card and the preamble

    func testYourClaimTodayAndItsProofDay() {
        let f: ChatFeed = feed(checkIns: [checkIn("me", 9, at: at(9, 9))])
        XCTAssertEqual(f.proofDay, 9)
        XCTAssertEqual(f.proofKind, .checkIn)
    }

    func testYesterdaysExcuseTakesProofToday() {
        let f: ChatFeed = feed(excuses: [excuse("me", 8, at: at(8, 9))])
        XCTAssertEqual(f.proofDay, 8)
        XCTAssertEqual(f.proofKind, .excuse("Sick"))
    }

    func testNoClaimMeansNoProofDay() {
        let f: ChatFeed = feed(checkIns: [checkIn("maya", 9, at: at(9, 9))])
        XCTAssertNil(f.proofDay)
        XCTAssertNil(f.proofKind)
    }

    func testVotersNeedTwoMembersToday() {
        XCTAssertTrue(feed().hasVoters)
        XCTAssertFalse(feed(members: [member("me", "Alex")]).hasVoters)
    }
}
