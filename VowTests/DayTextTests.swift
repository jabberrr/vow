import XCTest
@testable import Vow

final class DayTextTests: XCTestCase {
    private let en: Locale = Locale(identifier: "en_US")
    /// 2026-10-08 12:00 UTC.
    private let oct8: Date = Date(timeIntervalSince1970: 1_791_460_800)
    /// 2026-10-20 12:00 UTC.
    private let oct20: Date = Date(timeIntervalSince1970: 1_792_497_600)
    /// 2025-12-31 12:00 UTC.
    private let dec31: Date = Date(timeIntervalSince1970: 1_767_182_400)
    /// 2026-01-02 12:00 UTC.
    private let jan2: Date = Date(timeIntervalSince1970: 1_767_355_200)

    /// Created 2026-10-01 04:00 UTC (day 0 = Oct 1 in UTC).
    private func makeGroup(isTest: Bool, endDay: Int?) -> GroupInfo {
        return GroupInfo(id: GroupID(zoneName: "group-days", ownerName: "owner"),
                         name: "Read Nightly",
                         stake: 1,
                         createdAt: Date(timeIntervalSince1970: 1_790_827_200),
                         timeZoneID: "UTC",
                         isTest: isTest,
                         testDay: 0,
                         epoch: 0,
                         ownerUserID: "me",
                         shareURL: nil,
                         endDay: endDay)
    }

    func testDateInTheSameYearHasNoYear() {
        XCTAssertEqual(DayText.date(oct8, timeZoneID: "UTC", now: oct20, locale: en), "Oct 8")
    }

    func testDateInAnotherYearHasTheYear() {
        XCTAssertEqual(DayText.date(dec31, timeZoneID: "UTC", now: jan2, locale: en), "Dec 31, 2025")
    }

    func testDateFollowsTheGroupsTimeZone() {
        // 2026-10-08 18:00 UTC is already Oct 9, 03:00 in Tokyo.
        let evening: Date = oct8.addingTimeInterval(6 * 3600)
        XCTAssertEqual(DayText.date(evening, timeZoneID: "UTC", now: oct20, locale: en), "Oct 8")
        XCTAssertEqual(DayText.date(evening, timeZoneID: "Asia/Tokyo", now: oct20, locale: en), "Oct 9")
    }

    func testMonth() {
        XCTAssertEqual(DayText.month(oct8, timeZoneID: "UTC", locale: en), "October 2026")
    }

    func testSpokenDate() {
        XCTAssertEqual(DayText.spoken(oct8, timeZoneID: "UTC", locale: en), "October 8")
    }

    func testSinceToday() {
        XCTAssertEqual(DayText.since(oct20.addingTimeInterval(-6 * 3600), today: oct20, timeZoneID: "UTC", locale: en), "Since today")
    }

    func testSinceAnEarlierDay() {
        XCTAssertEqual(DayText.since(oct8, today: oct20, timeZoneID: "UTC", locale: en), "Since Oct 8")
    }

    func testFinalDayOfARealGroupIsADate() {
        XCTAssertEqual(DayText.finalDay(makeGroup(isTest: false, endDay: 29), now: oct20, locale: en), "Oct 30")
    }

    func testFinalDayOfATestGroupIsADayNumber() {
        XCTAssertEqual(DayText.finalDay(makeGroup(isTest: true, endDay: 29), now: oct20, locale: en), "Day 30")
    }

    func testNoFinalDayWithoutAnEnd() {
        XCTAssertNil(DayText.finalDay(makeGroup(isTest: false, endDay: nil), now: oct20, locale: en))
    }

    func testCount() {
        XCTAssertEqual(DayText.count(1), "1 day")
        XCTAssertEqual(DayText.count(30), "30 days")
    }
}
