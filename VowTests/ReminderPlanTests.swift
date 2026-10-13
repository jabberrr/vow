import XCTest
@testable import Vow

final class ReminderPlanTests: XCTestCase {
    private var calendar: Calendar {
        var cal: Calendar = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        return cal
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c: DateComponents = DateComponents()
        c.year = y
        c.month = mo
        c.day = d
        c.hour = h
        c.minute = mi
        return calendar.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    private func group(_ zone: String, _ name: String, kept: Bool, streak: Int) -> ReminderGroup {
        return ReminderGroup(id: GroupID(zoneName: zone, ownerName: "o"), name: name, keptToday: kept, streak: streak)
    }

    func testNoGroupsNoRequests() {
        XCTAssertTrue(ReminderPlan.requests(groups: [], minuteOfDay: 1200, now: date(2026, 10, 13, 10, 0), calendar: calendar).isEmpty)
    }

    func testOneOpenGroupToday() {
        let g: ReminderGroup = group("z1", "Morning Run", kept: false, streak: 12)
        let reqs: [ReminderRequest] = ReminderPlan.requests(groups: [g], minuteOfDay: 1200, now: date(2026, 10, 13, 10, 0), calendar: calendar)
        XCTAssertEqual(reqs.count, 7)
        XCTAssertEqual(reqs[0].id, "vow.reminder.2026-10-13")
        XCTAssertEqual(reqs[0].fireDate, date(2026, 10, 13, 20, 0))
        XCTAssertEqual(reqs[0].title, "Morning Run")
        XCTAssertEqual(reqs[0].body, "Hold the orb to keep your 12-day streak.")
        XCTAssertEqual(reqs[0].badge, 1)
        XCTAssertEqual(reqs[0].groupID, g.id)
        XCTAssertEqual(reqs[1].body, "Your vow is still open today.")
        XCTAssertEqual(reqs[6].id, "vow.reminder.2026-10-19")
    }

    func testKeptTodaySkipsToday() {
        let g: ReminderGroup = group("z1", "Morning Run", kept: true, streak: 13)
        let reqs: [ReminderRequest] = ReminderPlan.requests(groups: [g], minuteOfDay: 1200, now: date(2026, 10, 13, 10, 0), calendar: calendar)
        XCTAssertEqual(reqs.count, 6)
        XCTAssertEqual(reqs[0].id, "vow.reminder.2026-10-14")
    }

    func testPastTimeSkipsToday() {
        let g: ReminderGroup = group("z1", "Morning Run", kept: false, streak: 1)
        let reqs: [ReminderRequest] = ReminderPlan.requests(groups: [g], minuteOfDay: 1200, now: date(2026, 10, 13, 21, 0), calendar: calendar)
        XCTAssertEqual(reqs.first?.id, "vow.reminder.2026-10-14")
    }

    func testTwoOpenGroups() {
        let reqs: [ReminderRequest] = ReminderPlan.requests(
            groups: [group("z1", "A", kept: false, streak: 3), group("z2", "B", kept: false, streak: 0)],
            minuteOfDay: 1200, now: date(2026, 10, 13, 10, 0), calendar: calendar)
        XCTAssertEqual(reqs[0].title, "Vow")
        XCTAssertEqual(reqs[0].body, "2 vows are still open today.")
        XCTAssertEqual(reqs[0].badge, 2)
        XCTAssertNil(reqs[0].groupID)
    }

    func testBadgeOnlyAfterReminderTime() {
        let groups: [ReminderGroup] = [group("z1", "A", kept: false, streak: 3), group("z2", "B", kept: true, streak: 4)]
        XCTAssertEqual(ReminderPlan.badgeCount(groups: groups, minuteOfDay: 1200, now: date(2026, 10, 13, 10, 0), calendar: calendar), 0)
        XCTAssertEqual(ReminderPlan.badgeCount(groups: groups, minuteOfDay: 1200, now: date(2026, 10, 13, 20, 30), calendar: calendar), 1)
    }

    func testIdentifiersToClear() {
        let ids: [String] = ReminderPlan.identifiersToClear(now: date(2026, 10, 13, 10, 0), calendar: calendar)
        XCTAssertEqual(ids.count, 18)
        XCTAssertEqual(ids.first, "vow.reminder.2026-10-12")
        XCTAssertTrue(ids.contains("vow.badge.2026-10-12"))
        XCTAssertEqual(ids.last, "vow.badge.2026-10-20")
    }

    func testBadgeResetsAtEachMidnight() {
        let resets: [ReminderBadgeReset] = ReminderPlan.badgeResets(now: date(2026, 10, 13, 10, 0), calendar: calendar)
        XCTAssertEqual(resets.count, 7)
        XCTAssertEqual(resets[0].id, "vow.badge.2026-10-14")
        XCTAssertEqual(resets[0].fireDate, date(2026, 10, 14, 0, 0))
        XCTAssertEqual(resets[6].id, "vow.badge.2026-10-20")
    }

    func testSignatureChangesWithKeptState() {
        let open: String = ReminderPlan.signature([group("z1", "A", kept: false, streak: 3)])
        let kept: String = ReminderPlan.signature([group("z1", "A", kept: true, streak: 4)])
        XCTAssertEqual(open, "z1|A|false|3")
        XCTAssertNotEqual(open, kept)
    }
}
