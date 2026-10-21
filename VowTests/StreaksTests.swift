import XCTest
@testable import Vow

final class StreaksTests: XCTestCase {
    private let k: DayOutcome = .kept
    private let m: DayOutcome = .missed
    private let e: DayOutcome = .excused

    func testIsMilestone() {
        for n in [3, 7, 14, 30, 50, 100, 150, 200, 250, 300, 365, 400, 500, 1000] {
            XCTAssertTrue(StreakMilestones.isMilestone(n), "\(n)")
        }
        for n in [0, 1, 2, 4, 8, 13, 366, 450, 399] {
            XCTAssertFalse(StreakMilestones.isMilestone(n), "\(n)")
        }
    }

    func testNextAfter() {
        XCTAssertEqual(StreakMilestones.next(after: 0), 3)
        XCTAssertEqual(StreakMilestones.next(after: 3), 7)
        XCTAssertEqual(StreakMilestones.next(after: 12), 14)
        XCTAssertEqual(StreakMilestones.next(after: 364), 365)
        XCTAssertEqual(StreakMilestones.next(after: 365), 400)
        XCTAssertEqual(StreakMilestones.next(after: 400), 500)
        XCTAssertEqual(StreakMilestones.next(after: 999), 1000)
    }

    func testPreviousAtOrBelow() {
        XCTAssertEqual(StreakMilestones.previous(atOrBelow: 0), 0)
        XCTAssertEqual(StreakMilestones.previous(atOrBelow: 2), 0)
        XCTAssertEqual(StreakMilestones.previous(atOrBelow: 3), 3)
        XCTAssertEqual(StreakMilestones.previous(atOrBelow: 13), 7)
        XCTAssertEqual(StreakMilestones.previous(atOrBelow: 399), 365)
        XCTAssertEqual(StreakMilestones.previous(atOrBelow: 420), 400)
    }

    func testPreviousRecordIgnoresTheRunningRun() {
        XCTAssertEqual(StreakEvents.previousRecord([]), 0)
        XCTAssertEqual(StreakEvents.previousRecord([k, k, k, k, k]), 0)
        XCTAssertEqual(StreakEvents.previousRecord([k, k, m, k]), 2)
        XCTAssertEqual(StreakEvents.previousRecord([k, k, k, m, k, k, k, k, m, k]), 4)
    }

    func testExcusedDaysNeitherBreakNorExtendARecord() {
        XCTAssertEqual(StreakEvents.previousRecord([k, k, e, k, m, k]), 3)
        XCTAssertEqual(StreakEvents.previousRecord([k, m, e, k, k, e]), 1)
        XCTAssertEqual(StreakEvents.previousRecord([e, e, m]), 0)
        XCTAssertEqual(StreakEvents.event(streak: 5, history: [k, k, e, k, k, m, k, e, k, k, k]), .newBest(5))
    }

    func testMilestoneEvent() {
        XCTAssertEqual(StreakEvents.event(streak: 7, history: [k, k, k, k, k, k]), .milestone(7))
        XCTAssertEqual(StreakEvents.event(streak: 3, history: [k, k, m, k, k]), .milestone(3))
    }

    func testNewBestEvent() {
        XCTAssertEqual(StreakEvents.event(streak: 5, history: [k, k, k, k, m, k, k, k, k]), .newBest(5))
        XCTAssertNil(StreakEvents.event(streak: 6, history: [k, k, k, k, m, k, k, k, k, k]))
    }

    func testNoEventForSmallRecordsOrZero() {
        XCTAssertNil(StreakEvents.event(streak: 0, history: [m]))
        XCTAssertNil(StreakEvents.event(streak: 2, history: [k, m, k]))
        XCTAssertNil(StreakEvents.event(streak: 5, history: [k, k, m, k, k, k, k]))
    }
}
