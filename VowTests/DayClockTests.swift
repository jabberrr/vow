import XCTest
@testable import Vow

final class DayClockTests: XCTestCase {

    private let ny: String = "America/New_York"
    private let tokyo: String = "Asia/Tokyo"

    private func date(_ seconds: Double) -> Date {
        return Date(timeIntervalSince1970: seconds)
    }

    private func group(isTest: Bool, testDay: Int = 0, createdAt: Double, timeZoneID: String) -> GroupInfo {
        return GroupInfo(id: GroupID(zoneName: "group-clock", ownerName: "owner"),
                         name: "Clock",
                         stake: 1,
                         createdAt: date(createdAt),
                         timeZoneID: timeZoneID,
                         isTest: isTest,
                         testDay: testDay,
                         epoch: 0,
                         ownerUserID: "owner",
                         shareURL: nil)
    }

    func testCalendarUsesTimeZone() {
        let cal: Calendar = DayClock.calendar(tokyo)
        XCTAssertEqual(cal.timeZone.identifier, tokyo)
        XCTAssertEqual(cal.identifier, Calendar.Identifier.gregorian)
        XCTAssertEqual(DayClock.calendar("Not/AZone").timeZone, TimeZone.current)
        XCTAssertEqual(DayClock.graceSeconds, 600, accuracy: 0.001)
    }

    func testDayIndexAcrossSpringForward() {
        // 2026-03-07 12:00 EST; clocks jump forward 2026-03-08 02:00.
        let start: Date = date(1_772_902_800)
        XCTAssertEqual(DayClock.dayIndex(of: start, start: start, timeZoneID: ny), 0)
        XCTAssertEqual(DayClock.dayIndex(of: date(1_773_028_740), start: start, timeZoneID: ny), 1) // 03-08 23:59 EDT
        XCTAssertEqual(DayClock.dayIndex(of: date(1_773_030_600), start: start, timeZoneID: ny), 2) // 03-09 00:30 EDT (only 47.5h after start of day)
    }

    func testDayIndexAcrossFallBack() {
        // 2026-10-31 12:00 EDT; clocks fall back 2026-11-01 02:00.
        let start: Date = date(1_793_462_400)
        XCTAssertEqual(DayClock.dayIndex(of: date(1_793_593_800), start: start, timeZoneID: ny), 1) // 11-01 23:30 EST (48.5h after start of day)
        XCTAssertEqual(DayClock.dayIndex(of: date(1_793_596_200), start: start, timeZoneID: ny), 2) // 11-02 00:10 EST
    }

    func testDayIndexNeverNegative() {
        let start: Date = date(1_767_225_600)
        XCTAssertEqual(DayClock.dayIndex(of: date(1_767_225_600 - 86_400 * 3), start: start, timeZoneID: ny), 0)
    }

    func testDayIndexInNonLocalTimeZone() {
        // 2026-01-01T00:00Z = 09:00 in Tokyo.
        let start: Date = date(1_767_225_600)
        XCTAssertEqual(DayClock.dayIndex(of: date(1_767_279_540), start: start, timeZoneID: tokyo), 0) // 23:59 Tokyo
        XCTAssertEqual(DayClock.dayIndex(of: date(1_767_281_400), start: start, timeZoneID: tokyo), 1) // 00:30 Jan 2 Tokyo
        XCTAssertEqual(DayClock.dayIndex(of: date(1_767_281_400), start: start, timeZoneID: "UTC"), 0) // still Jan 1 in UTC
    }

    func testCurrentDayAndNextDayStartRealGroup() {
        let g: GroupInfo = group(isTest: false, createdAt: 1_767_225_600, timeZoneID: tokyo)
        let now: Date = date(1_767_281_400)
        XCTAssertEqual(DayClock.currentDay(g, now: now), 1)
        XCTAssertEqual(DayClock.nextDayStart(g, now: date(1_767_225_600)), date(1_767_279_600)) // 2026-01-02 00:00 Tokyo
    }

    func testNextDayStartAcrossDST() {
        let g: GroupInfo = group(isTest: false, createdAt: 1_772_902_800, timeZoneID: ny)
        // 2026-03-07 22:00 EST → 2026-03-08 00:00 EST
        XCTAssertEqual(DayClock.nextDayStart(g, now: date(1_772_938_800)), date(1_772_946_000))
        // 2026-03-08 10:00 EDT → 2026-03-09 00:00 EDT (a 23-hour day)
        XCTAssertEqual(DayClock.nextDayStart(g, now: date(1_772_978_400)), date(1_773_028_800))
        // 2026-11-01 09:00 EST → 2026-11-02 00:00 EST (a 25-hour day)
        XCTAssertEqual(DayClock.nextDayStart(g, now: date(1_793_541_600)), date(1_793_595_600))
    }

    func testTestGroupsUseTestDay() {
        let g: GroupInfo = group(isTest: true, testDay: 5, createdAt: 1_767_225_600, timeZoneID: ny)
        XCTAssertEqual(DayClock.currentDay(g, now: date(1_900_000_000)), 5)
        XCTAssertEqual(DayClock.currentDay(g, now: date(1_767_225_600)), 5)
        XCTAssertNil(DayClock.nextDayStart(g, now: date(1_767_225_600)))
    }
}
