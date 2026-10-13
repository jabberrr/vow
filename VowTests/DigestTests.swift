import XCTest
@testable import Vow

final class DigestTests: XCTestCase {
    private func line(_ id: String, _ day: Int, _ kind: LedgerLine.Kind, _ amount: Double?) -> LedgerLine {
        return LedgerLine(id: id, day: day, kind: kind, text: "", amount: amount)
    }

    private func standing(_ id: String, _ name: String, net: Double, history: [DayOutcome] = [], today: Bool = false) -> MemberStanding {
        return MemberStanding(userID: id, displayName: name, vow: "I will read", isActive: true, net: net,
                              streak: 0, bestStreak: 0, history: history, checkedInToday: today, missedYesterday: false)
    }

    func testViewerChangeSumsOnlyThatDaysOwnAmounts() {
        let ledger: [LedgerLine] = [
            line("a", 3, .missed, -2),
            line("b", 3, .payout, 1.33),
            line("c", 3, .kept, nil),
            line("d", 3, .forfeit, nil),
            line("e", 2, .payout, 5)
        ]
        XCTAssertEqual(Digest.viewerChange(ledger, day: 3), -0.67, accuracy: 0.0001)
        XCTAssertEqual(Digest.viewerChange(ledger, day: 2), 5, accuracy: 0.0001)
        XCTAssertEqual(Digest.viewerChange(ledger, day: 9), 0, accuracy: 0.0001)
    }

    func testDaysKeptCountsToday() {
        XCTAssertEqual(Digest.daysKept(standing("1", "A", net: 0, history: [.kept, .missed, .kept], today: true)), 3)
        XCTAssertEqual(Digest.daysKept(standing("1", "A", net: 0, history: [.missed], today: false)), 0)
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

    private func summary(day: Int, net: Double, ledger: [LedgerLine], kept: Bool, history: [DayOutcome], best: Int) -> GroupSummary {
        let viewer: MemberStanding = MemberStanding(userID: "me", displayName: "Me", vow: "I will read", isActive: true,
                                                    net: net, streak: 0, bestStreak: best, history: history,
                                                    checkedInToday: kept, missedYesterday: false)
        return GroupSummary(currentDay: day, cycle: day / 30 + 1, dayInCycle: day % 30 + 1, glyphNumber: day + 1,
                            pot: 0, totalForfeited: 0, standings: [viewer], ledger: ledger, viewer: viewer)
    }

    func testOverviewSkipsTestGroupsExceptInTheBalance() {
        let real: GroupID = GroupID(zoneName: "r", ownerName: "o")
        let test: GroupID = GroupID(zoneName: "t", ownerName: "o")
        let all: [GroupID: GroupSummary] = [
            real: summary(day: 4, net: 3, ledger: [line("a", 3, .payout, 1.5)], kept: true,
                          history: [.kept, .kept, .missed, .kept], best: 2),
            test: summary(day: 9, net: -2, ledger: [line("b", 8, .missed, -2)], kept: true,
                          history: [.kept, .kept, .kept, .kept, .kept], best: 5)
        ]
        let tests: Set<GroupID> = [test]
        XCTAssertEqual(Overview.balance(all), 1, accuracy: 0.0001)
        XCTAssertEqual(Overview.yesterdayChange(all, tests: tests), 1.5, accuracy: 0.0001)
        XCTAssertEqual(Overview.daysKept(all, tests: tests), 4)
        XCTAssertEqual(Overview.bestStreak(all, tests: tests), 2)
        XCTAssertEqual(Overview.vowCount(all), 2)
        XCTAssertEqual(Overview.keptTodayCount(all), 2)
    }
}
