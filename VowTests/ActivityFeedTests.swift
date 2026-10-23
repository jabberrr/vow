import XCTest
@testable import Vow

final class ActivityFeedTests: XCTestCase {
    private let en: Locale = Locale(identifier: "en_US")
    /// 2026-10-01 00:00 UTC, a Thursday: day 0 is Oct 1 in UTC.
    private let created: Date = Date(timeIntervalSince1970: 1_790_812_800)
    /// 2026-10-10 12:00 UTC: day 9.
    private let now: Date = Date(timeIntervalSince1970: 1_791_633_600)

    private let me: LedgerPerson = LedgerPerson(userID: "me", name: "Robin")
    private let alex: LedgerPerson = LedgerPerson(userID: "alex", name: "Alex")
    private let maya: LedgerPerson = LedgerPerson(userID: "maya", name: "Maya")
    private let sam: LedgerPerson = LedgerPerson(userID: "sam", name: "Sam")

    private func makeGroup(isTest: Bool = false, endDay: Int? = nil, createdAt: Date? = nil) -> GroupInfo {
        return GroupInfo(id: GroupID(zoneName: "group-activity", ownerName: "owner"),
                         name: "Morning Run",
                         stake: 2,
                         createdAt: createdAt ?? created,
                         timeZoneID: "UTC",
                         isTest: isTest,
                         testDay: 4,
                         epoch: 0,
                         ownerUserID: "me",
                         shareURL: nil,
                         endDay: endDay)
    }

    /// A day as Settlement lists it: `share` and `carriedOut` follow from the rest.
    private func ledgerDay(_ day: Int, isClosed: Bool = true, joined: [LedgerPerson] = [], left: [LedgerPerson] = [],
                           kept: [LedgerPerson] = [], excused: [LedgerPerson] = [], forfeits: [Forfeit] = [],
                           carriedIn: Double = 0) -> LedgerDay {
        var pot: Double = carriedIn
        for forfeit in forfeits {
            pot += forfeit.amount
        }
        return LedgerDay(day: day,
                         isClosed: isClosed,
                         joined: joined,
                         left: left,
                         kept: kept,
                         excused: excused,
                         forfeits: forfeits,
                         carriedIn: carriedIn,
                         share: kept.isEmpty ? 0 : pot / Double(kept.count),
                         carriedOut: kept.isEmpty ? pot : 0)
    }

    /// The group's stake of 2, lost.
    private func lost(_ person: LedgerPerson, _ reason: Forfeit.Reason = .missed) -> Forfeit {
        return Forfeit(person: person, reason: reason, amount: 2)
    }

    /// As the viewer "me", on day 9 unless told otherwise.
    private func build(_ days: [LedgerDay], group: GroupInfo? = nil, titleDay: Int = 9,
                       votingDay: Int? = nil, now: Date? = nil) -> [ActivitySection] {
        return ActivityFeed.build(days, group: group ?? makeGroup(), viewerID: "me", titleDay: titleDay,
                                  votingDay: votingDay, now: now ?? self.now, locale: en)
    }

    private func note(_ item: ActivityItem) -> String? {
        guard case .note(let note) = item else { return nil }
        return note.text
    }

    /// The flow `item` holds; a note fails the test.
    private func flow(_ item: ActivityItem) throws -> ActivityFlow {
        var found: ActivityFlow? = nil
        if case .flow(let flow) = item {
            found = flow
        }
        return try XCTUnwrap(found, "\(item.id) is a note")
    }

    private func texts(_ lines: [ActivityLine]) -> [String] {
        return lines.map { (line: ActivityLine) -> String in line.text }
    }

    private func amounts(_ lines: [ActivityLine]) -> [String] {
        return lines.map { (line: ActivityLine) -> String in line.amountText }
    }

    // MARK: - Arrows

    func testAStakeLostSendsOneArrowToEachKeeperYouFirst() throws {
        let day: LedgerDay = ledgerDay(8, kept: [me, sam], excused: [maya], forfeits: [lost(alex)])
        let sections: [ActivitySection] = build([day])

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Yesterday")
        XCTAssertEqual(sections[0].items.count, 2)
        XCTAssertEqual(note(sections[0].items[0]), "You and Sam kept · Maya was excused")
        let alexLost: ActivityFlow = try flow(sections[0].items[1])
        XCTAssertEqual(alexLost.source.text, "Alex missed")
        XCTAssertEqual(alexLost.source.amountText, "\u{2212}2 pts")
        XCTAssertFalse(alexLost.source.isViewer)
        XCTAssertEqual(texts(alexLost.arrows), ["You", "Sam"])
        XCTAssertEqual(amounts(alexLost.arrows), ["+1 pt", "+1 pt"])
        XCTAssertTrue(alexLost.arrows[0].isViewer)
        XCTAssertFalse(alexLost.arrows[1].isViewer)
        XCTAssertEqual(alexLost.spoken, "Alex missed, minus 2 points. 1 point to you, 1 point to Sam")
    }

    func testPartsSplitEvenlyAndRound() throws {
        let day: LedgerDay = ledgerDay(8, kept: [maya, me, sam], forfeits: [lost(alex)])
        let alexLost: ActivityFlow = try flow(build([day])[0].items[1])

        XCTAssertEqual(texts(alexLost.arrows), ["You", "Maya", "Sam"])
        XCTAssertEqual(alexLost.arrows[0].amount, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(amounts(alexLost.arrows), ["+0.67 pts", "+0.67 pts", "+0.67 pts"])
    }

    func testYourOwnStakeComesFirstInYourColour() throws {
        let day: LedgerDay = ledgerDay(8, kept: [sam], forfeits: [lost(maya), lost(me, .checkInOverruled)])
        let items: [ActivityItem] = build([day])[0].items

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(note(items[0]), "Sam kept")
        let mine: ActivityFlow = try flow(items[1])
        XCTAssertEqual(mine.source.text, "Your check-in was overruled")
        XCTAssertTrue(mine.source.isViewer)
        XCTAssertEqual(mine.source.amount, -2, accuracy: 1e-9)
        XCTAssertEqual(texts(mine.arrows), ["Sam"])
        XCTAssertEqual(amounts(mine.arrows), ["+2 pts"])
        XCTAssertEqual(try flow(items[2]).source.text, "Maya missed")
    }

    func testEveryReasonForAStakeLost() {
        XCTAssertEqual(ActivityFeed.forfeitText(lost(me), viewerID: "me"), "You missed")
        XCTAssertEqual(ActivityFeed.forfeitText(lost(maya), viewerID: "me"), "Maya missed")
        XCTAssertEqual(ActivityFeed.forfeitText(lost(me, .checkInOverruled), viewerID: "me"), "Your check-in was overruled")
        XCTAssertEqual(ActivityFeed.forfeitText(lost(maya, .checkInOverruled), viewerID: "me"),
                       "Maya's check-in was overruled")
        XCTAssertEqual(ActivityFeed.forfeitText(lost(me, .excuseOverruled), viewerID: "me"), "Your excuse was overruled")
        XCTAssertEqual(ActivityFeed.forfeitText(lost(maya, .excuseOverruled), viewerID: "me"),
                       "Maya's excuse was overruled")
    }

    // MARK: - The pot

    func testWithNobodyKeepingEachStakeGoesOnToTheNextDay() throws {
        let day: LedgerDay = ledgerDay(6, excused: [me], forfeits: [lost(maya), lost(sam, .excuseOverruled)])
        let section: ActivitySection = build([day])[0]

        XCTAssertEqual(section.title, "Wed, Oct 7")
        XCTAssertEqual(note(section.items[0]), "Nobody kept · You were excused")
        let mayaLost: ActivityFlow = try flow(section.items[1])
        XCTAssertEqual(texts(mayaLost.arrows), ["Carried to Thu, Oct 8"])
        XCTAssertEqual(amounts(mayaLost.arrows), ["2 pts"])
        XCTAssertFalse(mayaLost.arrows[0].isViewer)
        XCTAssertEqual(mayaLost.spoken, "Maya missed, minus 2 points. 2 points carried to Thu, Oct 8")
        XCTAssertEqual(try flow(section.items[2]).source.text, "Sam's excuse was overruled")
    }

    func testACarryNamesTodayAndYesterday() throws {
        let yesterday: LedgerDay = ledgerDay(8, forfeits: [lost(maya)])
        let before: LedgerDay = ledgerDay(7, forfeits: [lost(maya)])
        let sections: [ActivitySection] = build([yesterday, before])

        XCTAssertEqual(texts(try flow(sections[0].items[1]).arrows), ["Carried to today"])
        XCTAssertEqual(texts(try flow(sections[1].items[1]).arrows), ["Carried to yesterday"])
    }

    func testTheCarriedPotGoesToTheKeepersBeforeTheDaysStakes() throws {
        let day: LedgerDay = ledgerDay(8, kept: [me, sam], forfeits: [lost(alex)], carriedIn: 4)
        let items: [ActivityItem] = build([day])[0].items

        XCTAssertEqual(items.count, 3)
        let carried: ActivityFlow = try flow(items[1])
        XCTAssertEqual(carried.source.text, "Carried over from earlier days")
        XCTAssertEqual(carried.source.amountText, "4 pts")
        XCTAssertFalse(carried.source.isViewer)
        XCTAssertEqual(texts(carried.arrows), ["You", "Sam"])
        XCTAssertEqual(amounts(carried.arrows), ["+2 pts", "+2 pts"])
        XCTAssertEqual(carried.spoken, "Carried over from earlier days, 4 points. 2 points to you, 2 points to Sam")
        XCTAssertEqual(try flow(items[2]).source.text, "Alex missed")
    }

    func testAPotNobodyKeptPassesThroughUnseen() throws {
        let excused: LedgerDay = ledgerDay(7, excused: [maya, me], carriedIn: 4)
        let missed: LedgerDay = ledgerDay(6, forfeits: [lost(maya)], carriedIn: 2)
        let sections: [ActivitySection] = build([excused, missed])

        XCTAssertEqual(sections[0].items.count, 1)
        XCTAssertEqual(sections[0].quietNote?.text, "Everyone was excused")
        XCTAssertEqual(sections[1].items.count, 2)
        XCTAssertEqual(try flow(sections[1].items[1]).source.text, "Maya missed")
        XCTAssertEqual(amounts(try flow(sections[1].items[1]).arrows), ["2 pts"])
    }

    func testAfterTheFinalDayThePotStays() throws {
        let day: LedgerDay = ledgerDay(7, forfeits: [lost(maya)])
        let mayaLost: ActivityFlow = try flow(build([day], group: makeGroup(endDay: 7))[0].items[1])

        XCTAssertEqual(texts(mayaLost.arrows), ["Left in the pot"])
        XCTAssertEqual(mayaLost.spoken, "Maya missed, minus 2 points. 2 points left in the pot")
    }

    // MARK: - Notes

    func testADayEveryoneKeptIsOneQuietNote() {
        let both: ActivitySection = build([ledgerDay(5, kept: [maya, me])])[0]
        XCTAssertEqual(both.title, "Tue, Oct 6")
        XCTAssertEqual(both.quietNote?.text, "Everyone kept")
        XCTAssertEqual(both.spokenTitle, "Tue, Oct 6")

        let solo: ActivitySection = build([ledgerDay(5, kept: [me])])[0]
        XCTAssertEqual(solo.quietNote?.text, "You kept")
    }

    func testOpenVotesKeepTheHeaderOnItsOwnLine() {
        let section: ActivitySection = build([ledgerDay(8, kept: [maya, me])], votingDay: 8)[0]

        XCTAssertTrue(section.votesOpen)
        XCTAssertNil(section.quietNote)
        XCTAssertEqual(section.spokenTitle, "Yesterday, votes still open")
    }

    func testWhoWasExcused() {
        XCTAssertEqual(ActivityFeed.outcome(ledgerDay(8, kept: [maya], excused: [me]), viewerID: "me"),
                       "Maya kept · You were excused")
        XCTAssertEqual(ActivityFeed.outcome(ledgerDay(8, kept: [me], excused: [maya, sam]), viewerID: "me"),
                       "You kept · Maya and Sam were excused")
        XCTAssertEqual(ActivityFeed.outcome(ledgerDay(8, excused: [me]), viewerID: "me"), "You were excused")
        XCTAssertEqual(ActivityFeed.outcome(ledgerDay(8, excused: [maya]), viewerID: "me"), "Maya was excused")
    }

    func testJoinsAndLeavesCloseTheDay() {
        let today: ActivitySection = build([ledgerDay(9, isClosed: false, joined: [alex], left: [sam])])[0]
        XCTAssertEqual(today.title, "Today")
        XCTAssertEqual(today.quietNote?.text, "Alex joined · Sam left")

        let first: ActivitySection = build([ledgerDay(0, joined: [maya, me], kept: [maya, me])])[0]
        XCTAssertEqual(first.items.map { (item: ActivityItem) -> String? in note(item) },
                       ["Everyone kept", "You and Maya joined"])
        XCTAssertNil(first.quietNote)
    }

    func testADayWithNothingInItIsLeftOut() {
        let sections: [ActivitySection] = build([ledgerDay(8, kept: [me]), ledgerDay(7), ledgerDay(6, kept: [me])])
        XCTAssertEqual(sections.map { (section: ActivitySection) -> Int in section.day }, [8, 6])
    }

    func testNames() {
        XCTAssertEqual(ActivityFeed.names([], viewerID: "me"), "")
        XCTAssertEqual(ActivityFeed.names([maya], viewerID: "me"), "Maya")
        XCTAssertEqual(ActivityFeed.names([maya, me, sam], viewerID: "me"), "You, Maya and Sam")
        XCTAssertEqual(ActivityFeed.name(LedgerPerson(userID: "x", name: "  Jo  "), viewerID: "me"), "Jo")
        XCTAssertEqual(ActivityFeed.name(LedgerPerson(userID: "x", name: " "), viewerID: "me"), "Someone")
    }

    // MARK: - Titles

    func testATestGroupCountsItsDays() throws {
        let group: GroupInfo = makeGroup(isTest: true)
        let sections: [ActivitySection] = build([ledgerDay(3, kept: [me]), ledgerDay(1, forfeits: [lost(maya)])],
                                                group: group, titleDay: 4)

        XCTAssertEqual(sections[0].title, "Yesterday")
        XCTAssertEqual(sections[1].title, "Day 2")
        XCTAssertEqual(texts(try flow(sections[1].items[1]).arrows), ["Carried to Day 3"])
    }

    func testADayInAnotherYearShowsItsYear() {
        // 2025-12-30 00:00 UTC is day 0; 2026-01-03 12:00 UTC is day 4.
        let group: GroupInfo = makeGroup(createdAt: Date(timeIntervalSince1970: 1_767_052_800))
        let sections: [ActivitySection] = build([ledgerDay(2, kept: [me]), ledgerDay(1, kept: [me])],
                                                group: group, titleDay: 4,
                                                now: Date(timeIntervalSince1970: 1_767_441_600))

        XCTAssertEqual(sections[0].title, "Thu, Jan 1")
        XCTAssertEqual(sections[1].title, "Wed, Dec 31, 2025")
    }
}
