import XCTest
@testable import Vow

final class CycleChainTests: XCTestCase {
    private let k: DayOutcome = .kept
    private let m: DayOutcome = .missed
    private let e: DayOutcome = .excused

    func testFirstCycle() {
        let beads: [ChainBead] = CycleChain.beads(history: [k, k, m, k, k], currentDay: 5, checkedInToday: false)
        XCTAssertEqual(beads.count, 30)
        XCTAssertEqual(beads[0], .kept(day: 0))
        XCTAssertEqual(beads[2], .missed(day: 2))
        XCTAssertEqual(beads[4], .kept(day: 4))
        XCTAssertEqual(beads[5], .today(day: 5, kept: false))
        XCTAssertEqual(beads[6], .upcoming)
        XCTAssertEqual(beads[29], .upcoming)
    }

    func testSecondCycleWithLateJoin() {
        // Joined on day 32; days 32...34 closed; today is day 35.
        let beads: [ChainBead] = CycleChain.beads(history: [k, m, k], currentDay: 35, checkedInToday: true)
        XCTAssertEqual(beads[0], .notJoined)
        XCTAssertEqual(beads[1], .notJoined)
        XCTAssertEqual(beads[2], .kept(day: 32))
        XCTAssertEqual(beads[3], .missed(day: 33))
        XCTAssertEqual(beads[4], .kept(day: 34))
        XCTAssertEqual(beads[5], .today(day: 35, kept: true))
        XCTAssertEqual(beads[6], .upcoming)
    }

    func testDayZero() {
        let beads: [ChainBead] = CycleChain.beads(history: [], currentDay: 0, checkedInToday: false)
        XCTAssertEqual(beads[0], .today(day: 0, kept: false))
        XCTAssertEqual(beads[1], .upcoming)
    }

    func testExcusedDaysGetTheirOwnBead() {
        let beads: [ChainBead] = CycleChain.beads(history: [k, e, m], currentDay: 3, checkedInToday: false)
        XCTAssertEqual(beads[0], .kept(day: 0))
        XCTAssertEqual(beads[1], .excused(day: 1))
        XCTAssertEqual(beads[2], .missed(day: 2))
        XCTAssertEqual(CycleChain.summaryText(beads), "This cycle: 1 kept, 1 missed, 1 excused, today open")
    }

    func testSummaryText() {
        let beads: [ChainBead] = CycleChain.beads(history: [k, k, m], currentDay: 3, checkedInToday: false)
        XCTAssertEqual(CycleChain.summaryText(beads), "This cycle: 2 kept, 1 missed, today open")
    }
}
