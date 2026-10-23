import XCTest
@testable import Vow

final class VowStatusTests: XCTestCase {
    /// 2026-10-20 14:00 UTC: 10 h left in a UTC group's day.
    private let afternoon: Date = Date(timeIntervalSince1970: 1_792_504_800)
    /// 2026-10-20 21:00 UTC: 3 h left.
    private let evening: Date = Date(timeIntervalSince1970: 1_792_530_000)

    private func makeGroup(_ zone: String, name: String, isTest: Bool = false) -> GroupInfo {
        return GroupInfo(id: GroupID(zoneName: zone, ownerName: "owner"),
                         name: name,
                         stake: 2,
                         createdAt: Date(timeIntervalSince1970: 1_790_827_200),
                         timeZoneID: "UTC",
                         isTest: isTest,
                         testDay: 0,
                         epoch: 0,
                         ownerUserID: "me",
                         shareURL: nil)
    }

    private func me(kept: Bool, excused: Bool = false, overruled: Bool = false) -> MemberStanding {
        return MemberStanding(userID: "me", displayName: "Ava", vow: "I will read", isActive: true, net: 0,
                              streak: kept && !overruled ? 1 : 0, bestStreak: 1, history: [], checkedInToday: kept,
                              missedYesterday: false, excusedToday: excused, todayOverruled: overruled)
    }

    private func summary(_ viewer: MemberStanding?, finished: Bool = false) -> GroupSummary {
        var standings: [MemberStanding] = []
        if let v: MemberStanding = viewer {
            standings.append(v)
        }
        return GroupSummary(currentDay: 19, cycle: 1, dayInCycle: 20, glyphNumber: 20, pot: 0, totalForfeited: 0,
                            standings: standings, days: [], viewer: viewer, endDay: nil, isFinished: finished)
    }

    func testFinishedWinsOverEverything() {
        let group: GroupInfo = makeGroup("a", name: "A")
        XCTAssertEqual(Overview.status(summary(me(kept: false), finished: true), group: group, now: evening, holdingLight: false), .finished)
        XCTAssertEqual(Overview.status(summary(nil, finished: true), group: group, now: afternoon, holdingLight: false), .finished)
    }

    func testNotJoined() {
        XCTAssertEqual(Overview.status(summary(nil), group: makeGroup("a", name: "A"), now: afternoon, holdingLight: false), .notJoined)
    }

    func testKeptUnlessItsLightIsHeld() {
        let group: GroupInfo = makeGroup("a", name: "A")
        XCTAssertEqual(Overview.status(summary(me(kept: true)), group: group, now: afternoon, holdingLight: false), .kept)
        XCTAssertEqual(Overview.status(summary(me(kept: true)), group: group, now: afternoon, holdingLight: true), .open)
    }

    func testExcusedAndOverruled() {
        let group: GroupInfo = makeGroup("a", name: "A")
        func status(_ viewer: MemberStanding, holdingLight: Bool = false) -> VowStatus {
            return Overview.status(summary(viewer), group: group, now: evening, holdingLight: holdingLight)
        }
        XCTAssertEqual(status(me(kept: false, excused: true)), .excused)
        XCTAssertEqual(status(me(kept: false, excused: true, overruled: true)), .overruled)
        XCTAssertEqual(status(me(kept: true, overruled: true)), .overruled)
        // A check-in whose light is still held reads as your turn, whatever the votes.
        XCTAssertEqual(status(me(kept: true, overruled: true), holdingLight: true), .atRisk)
        XCTAssertEqual(Overview.status(summary(me(kept: false, excused: true), finished: true), group: group, now: evening,
                                       holdingLight: false), .finished)
    }

    func testMenuDotSkipsExcusedAndOverruledVows() {
        let groups: [GroupInfo] = [makeGroup("a", name: "Sick Day"), makeGroup("b", name: "Voted Down"),
                                   makeGroup("c", name: "Gym")]
        var all: [GroupID: GroupSummary] = [:]
        all[groups[0].id] = summary(me(kept: false, excused: true))
        all[groups[1].id] = summary(me(kept: true, overruled: true))
        all[groups[2].id] = summary(me(kept: false))
        XCTAssertEqual(Overview.menuDot(all, groups: groups, selected: nil, now: evening), MenuDot(names: ["Gym"], atRisk: true))
    }

    func testAtRiskOnlyInTheLastFourHours() {
        let group: GroupInfo = makeGroup("a", name: "A")
        XCTAssertEqual(Overview.status(summary(me(kept: false)), group: group, now: afternoon, holdingLight: false), .open)
        XCTAssertEqual(Overview.status(summary(me(kept: false)), group: group, now: evening, holdingLight: false), .atRisk)
    }

    func testTestGroupsAreNeverAtRisk() {
        let group: GroupInfo = makeGroup("t", name: "T", isTest: true)
        XCTAssertEqual(Overview.status(summary(me(kept: false)), group: group, now: evening, holdingLight: false), .open)
    }

    func testMenuDotListsOnlyYourOtherOpenVows() {
        let groups: [GroupInfo] = [makeGroup("a", name: "Morning Run"), makeGroup("b", name: "Read Nightly"),
                                   makeGroup("c", name: "Selected"), makeGroup("d", name: "Done"),
                                   makeGroup("e", name: "Pending"), makeGroup("f", name: "Gym")]
        var all: [GroupID: GroupSummary] = [:]
        all[groups[0].id] = summary(me(kept: false))
        all[groups[1].id] = summary(me(kept: true))
        all[groups[2].id] = summary(me(kept: false))
        all[groups[3].id] = summary(me(kept: false), finished: true)
        all[groups[4].id] = summary(nil)
        all[groups[5].id] = summary(me(kept: false))
        let dot: MenuDot? = Overview.menuDot(all, groups: groups, selected: groups[2].id, now: afternoon)
        XCTAssertEqual(dot, MenuDot(names: ["Morning Run", "Gym"], atRisk: false))
    }

    func testMenuDotIsAtRiskWhenOneOtherVowIs() {
        let groups: [GroupInfo] = [makeGroup("a", name: "Morning Run"), makeGroup("t", name: "Test", isTest: true)]
        var all: [GroupID: GroupSummary] = [:]
        all[groups[0].id] = summary(me(kept: false))
        all[groups[1].id] = summary(me(kept: false))
        XCTAssertEqual(Overview.menuDot(all, groups: groups, selected: nil, now: evening)?.atRisk, true)
    }

    func testNoMenuDotWhenNothingElseIsOpen() {
        let groups: [GroupInfo] = [makeGroup("a", name: "A"), makeGroup("b", name: "B")]
        var all: [GroupID: GroupSummary] = [:]
        all[groups[0].id] = summary(me(kept: false))
        all[groups[1].id] = summary(me(kept: true))
        XCTAssertNil(Overview.menuDot(all, groups: groups, selected: groups[0].id, now: afternoon))
    }

    func testMenuDotSpokenValue() {
        XCTAssertEqual(MenuDot(names: ["Read Nightly"], atRisk: false).spoken, "Read Nightly is still open")
        XCTAssertEqual(MenuDot(names: ["A", "B"], atRisk: true).spoken, "2 other vows are still open")
    }

    func testThemeOfADayMatchesTheOrbsSeed() {
        XCTAssertEqual(Overview.theme(day: 29), DailyTheme.make(cycle: 1, day: 30))
        XCTAssertEqual(Overview.theme(day: 30), DailyTheme.make(cycle: 2, day: 1))
    }
}
