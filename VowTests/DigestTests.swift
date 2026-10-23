import XCTest
@testable import Vow

final class DigestTests: XCTestCase {
    private let ari: LedgerPerson = LedgerPerson(userID: "me", name: "Ari")
    private let maya: LedgerPerson = LedgerPerson(userID: "maya", name: "Maya")
    private let theo: LedgerPerson = LedgerPerson(userID: "theo", name: "Theo")

    private func closed(_ day: Int, kept: [LedgerPerson] = [], excused: [LedgerPerson] = [], forfeits: [Forfeit] = [],
                        share: Double = 0) -> LedgerDay {
        return LedgerDay(day: day, isClosed: true, joined: [], left: [], kept: kept, excused: excused, forfeits: forfeits,
                         carriedIn: 0, share: share, carriedOut: 0)
    }

    private func standing(_ id: String, _ name: String, net: Double, history: [DayOutcome] = [], today: Bool = false,
                          excused: Bool = false, overruled: Bool = false) -> MemberStanding {
        return MemberStanding(userID: id, displayName: name, vow: "I will read", isActive: true, net: net,
                              streak: 0, bestStreak: 0, history: history, checkedInToday: today, missedYesterday: false,
                              excusedToday: excused, todayOverruled: overruled)
    }

    func testViewerChangeIsTheShareKeptOrTheStakeLost() {
        let days: [LedgerDay] = [
            closed(4, kept: [maya], excused: [ari], forfeits: [Forfeit(person: theo, reason: .missed, amount: 2)],
                   share: 2),
            closed(3, kept: [ari, maya], forfeits: [Forfeit(person: theo, reason: .excuseOverruled, amount: 2)], share: 1),
            closed(2, kept: [maya], forfeits: [Forfeit(person: ari, reason: .checkInOverruled, amount: 2)], share: 2)
        ]
        XCTAssertEqual(Digest.viewerChange(days, day: 3, viewerID: "me"), 1, accuracy: 1e-9)
        XCTAssertEqual(Digest.viewerChange(days, day: 2, viewerID: "me"), -2, accuracy: 1e-9)
        XCTAssertEqual(Digest.viewerChange(days, day: 4, viewerID: "me"), 0, accuracy: 1e-9)      // excused
        XCTAssertEqual(Digest.viewerChange(days, day: 3, viewerID: "theo"), -2, accuracy: 1e-9)
        XCTAssertEqual(Digest.viewerChange(days, day: 4, viewerID: "maya"), 2, accuracy: 1e-9)
        XCTAssertEqual(Digest.viewerChange(days, day: 9, viewerID: "me"), 0, accuracy: 1e-9)      // not listed
        XCTAssertEqual(Digest.viewerChange(days, day: 3, viewerID: "stranger"), 0, accuracy: 1e-9)
    }

    func testDaysKeptCountsToday() {
        XCTAssertEqual(Digest.daysKept(standing("1", "A", net: 0, history: [.kept, .missed, .kept], today: true)), 3)
        XCTAssertEqual(Digest.daysKept(standing("1", "A", net: 0, history: [.missed], today: false)), 0)
    }

    func testOnlyStandingCheckInsCountAsKept() {
        let standings: [MemberStanding] = [
            standing("1", "A", net: 0, today: true),
            standing("2", "B", net: 0, today: true, overruled: true),
            standing("3", "C", net: 0, excused: true),
            standing("4", "D", net: 0)
        ]
        XCTAssertTrue(Digest.checkInStands(standings[0]))
        XCTAssertFalse(Digest.checkInStands(standings[1]))
        XCTAssertFalse(Digest.checkInStands(standings[2]))

        let history: [DayOutcome] = [.kept, .excused, .missed, .kept]
        XCTAssertEqual(Digest.daysKept(standing("1", "A", net: 0, history: history, today: true)), 3)
        XCTAssertEqual(Digest.daysKept(standing("1", "A", net: 0, history: history, today: true, overruled: true)), 2)
        XCTAssertEqual(Digest.daysKept(standing("1", "A", net: 0, history: history, excused: true)), 2)
    }

    func testOnlyStandingExcusesSitTodayOut() {
        let standings: [MemberStanding] = [
            standing("1", "A", net: 0, excused: true),
            standing("2", "B", net: 0, excused: true, overruled: true),
            standing("3", "C", net: 0, today: true),
            standing("4", "D", net: 0),
            standing("5", "E", net: 0, excused: true)
        ]
        XCTAssertTrue(Digest.excuseStands(standings[0]))
        XCTAssertFalse(Digest.excuseStands(standings[1]))
        XCTAssertFalse(Digest.excuseStands(standings[2]))
        XCTAssertFalse(Digest.excuseStands(standings[3]))
        XCTAssertTrue(Digest.excuseStands(standings[4]))
    }

    func testAnExcuseClosesToday() {
        func open(_ viewer: MemberStanding) -> Bool {
            return Digest.isOpen(GroupSummary(currentDay: 4, cycle: 1, dayInCycle: 5, glyphNumber: 5, pot: 0,
                                              totalForfeited: 0, standings: [viewer], days: [], viewer: viewer))
        }
        XCTAssertTrue(open(standing("me", "Me", net: 0)))
        XCTAssertFalse(open(standing("me", "Me", net: 0, excused: true)))
        XCTAssertFalse(open(standing("me", "Me", net: 0, excused: true, overruled: true)))
        XCTAssertFalse(open(standing("me", "Me", net: 0, today: true, overruled: true)))
    }

    func testSpan() {
        XCTAssertEqual(DayWindow.span(18_720), "5h 12m")
        XCTAssertEqual(DayWindow.span(7_200), "2h")
        XCTAssertEqual(DayWindow.span(1_080), "18m")
        XCTAssertNil(DayWindow.span(30))
    }

    func testAtRisk() {
        let created: Date = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
        var group: GroupInfo = GroupInfo(id: GroupID(zoneName: "z", ownerName: "o"), name: "G", stake: 2,
                                         createdAt: created, timeZoneID: "UTC", isTest: false, testDay: 0,
                                         epoch: 0, ownerUserID: "me", shareURL: nil)
        let evening: Date = created.addingTimeInterval(22 * 3600)   // 22:00 UTC, 2 h left
        let morning: Date = created.addingTimeInterval(9 * 3600)    // 09:00 UTC, 15 h left
        XCTAssertTrue(DayWindow.isAtRisk(group, now: evening))
        XCTAssertFalse(DayWindow.isAtRisk(group, now: morning))
        group.isTest = true
        XCTAssertFalse(DayWindow.isAtRisk(group, now: evening))
    }

    private func summary(day: Int, net: Double, days: [LedgerDay], kept: Bool, history: [DayOutcome], best: Int) -> GroupSummary {
        let viewer: MemberStanding = MemberStanding(userID: "me", displayName: "Me", vow: "I will read", isActive: true,
                                                    net: net, streak: 0, bestStreak: best, history: history,
                                                    checkedInToday: kept, missedYesterday: false)
        return GroupSummary(currentDay: day, cycle: day / 30 + 1, dayInCycle: day % 30 + 1, glyphNumber: day + 1,
                            pot: 0, totalForfeited: 0, standings: [viewer], days: days, viewer: viewer)
    }

    func testOverviewSkipsTestGroupsExceptInTheBalance() {
        let real: GroupID = GroupID(zoneName: "r", ownerName: "o")
        let test: GroupID = GroupID(zoneName: "t", ownerName: "o")
        let all: [GroupID: GroupSummary] = [
            real: summary(day: 4, net: 3, days: [closed(3, kept: [ari], share: 1.5)], kept: true,
                          history: [.kept, .kept, .missed, .kept], best: 2),
            test: summary(day: 9, net: -2, days: [closed(8, forfeits: [Forfeit(person: ari, reason: .missed, amount: 2)])],
                          kept: true, history: [.kept, .kept, .kept, .kept, .kept], best: 5)
        ]
        let tests: Set<GroupID> = [test]
        XCTAssertEqual(Overview.balance(all), 1, accuracy: 0.0001)
        XCTAssertEqual(Overview.yesterdayChange(all, tests: tests), 1.5, accuracy: 0.0001)
        XCTAssertEqual(Overview.daysKept(all, tests: tests), 4)
        XCTAssertEqual(Overview.bestStreak(all, tests: tests), 2)
    }
}
