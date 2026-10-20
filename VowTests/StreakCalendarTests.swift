import XCTest
@testable import Vow

final class StreakCalendarTests: XCTestCase {

    // MARK: - Fixtures

    /// 2026-01-01T00:00:00Z = 2025-12-31 19:00 in New York: day 0 is Wed Dec 31, day 1 Thu Jan 1,
    /// day 31 Sat Jan 31, day 32 Sun Feb 1, day 40 Mon Feb 9.
    private let created: Date = Date(timeIntervalSince1970: 1_767_225_600)
    private let ny: String = "America/New_York"
    /// 2027-01-15T08:00:00Z (03:00 in New York): any moment for test groups, which ignore the clock.
    private let anyNow: Date = Date(timeIntervalSince1970: 1_800_000_000)

    private func date(_ seconds: Double) -> Date {
        return Date(timeIntervalSince1970: seconds)
    }

    private func makeGroup(isTest: Bool = true, testDay: Int = 0, endDay: Int? = nil, createdAt: Date? = nil) -> GroupInfo {
        return GroupInfo(id: GroupID(zoneName: "group-calendar", ownerName: "owner"),
                         name: "Calendar",
                         stake: 2,
                         createdAt: createdAt ?? created,
                         timeZoneID: ny,
                         isTest: isTest,
                         testDay: testDay,
                         epoch: 0,
                         ownerUserID: "me",
                         shareURL: nil,
                         endDay: endDay)
    }

    /// Gregorian with a pinned time zone and first weekday (1 = Sunday, 2 = Monday).
    private func calendar(firstWeekday: Int, timeZoneID: String? = nil) -> Calendar {
        var cal: Calendar = DayClock.calendar(timeZoneID ?? ny)
        cal.firstWeekday = firstWeekday
        return cal
    }

    private struct Layout {
        let summary: GroupSummary
        let standing: MemberStanding
        let months: [CalendarMonth]
    }

    /// Settles a one-member group ("me", kept on `kept` days) and lays out its calendar.
    private func layout(_ group: GroupInfo, kept: [Int], joinedDay: Int = 0, firstWeekday: Int = 1,
                        now: Date? = nil) throws -> Layout {
        let me: MemberInfo = MemberInfo(userID: "me", displayName: "Ari", vow: "I will read", joinedDay: joinedDay,
                                        joinedEpoch: 0, leftDay: nil)
        var checkIns: [CheckInInfo] = []
        for day in kept {
            checkIns.append(CheckInInfo(userID: "me", day: day, epoch: 0, serverDate: nil))
        }
        let snapshot: GroupSnapshot = GroupSnapshot(group: group, members: [me], checkIns: checkIns, fetchedAt: created)
        let summary: GroupSummary = Settlement.summarize(snapshot, viewerID: "me", now: now ?? anyNow)
        let standing: MemberStanding = try XCTUnwrap(summary.viewer)
        let months: [CalendarMonth] = StreakCalendar.months(group: group, summary: summary, standing: standing,
                                                            calendar: calendar(firstWeekday: firstWeekday))
        return Layout(summary: summary, standing: standing, months: months)
    }

    private func countDays(_ months: [CalendarMonth], _ test: (CalendarDay) -> Bool) -> Int {
        var n: Int = 0
        for month in months {
            for day in month.days where test(day) {
                n += 1
            }
        }
        return n
    }

    // MARK: - Month span and week layout

    func testMonthSpanAndLeadingBlanks() throws {
        let sunday: Layout = try layout(makeGroup(testDay: 3), kept: [0, 2], firstWeekday: 1)
        XCTAssertEqual(sunday.months.count, 2)
        XCTAssertEqual(sunday.months[0].start, date(1_764_565_200))   // Mon 2025-12-01 00:00 EST
        XCTAssertEqual(sunday.months[1].start, date(1_767_243_600))   // Thu 2026-01-01 00:00 EST
        XCTAssertEqual(sunday.months[0].id, sunday.months[0].start)
        XCTAssertEqual(sunday.months[0].leadingBlanks, 1)
        XCTAssertEqual(sunday.months[1].leadingBlanks, 4)
        XCTAssertEqual(sunday.months[0].days.count, 31)
        XCTAssertEqual(sunday.months[1].days.count, 31)
        XCTAssertEqual(sunday.months[0].days.first?.dayNumber, 1)
        XCTAssertEqual(sunday.months[0].days.last?.dayNumber, 31)
        XCTAssertEqual(sunday.months[0].days.first?.date, sunday.months[0].start)

        let monday: Layout = try layout(makeGroup(testDay: 3), kept: [0, 2], firstWeekday: 2)
        XCTAssertEqual(monday.months.count, 2)
        XCTAssertEqual(monday.months[0].leadingBlanks, 0)
        XCTAssertEqual(monday.months[1].leadingBlanks, 3)
        XCTAssertEqual(monday.months[0].days, sunday.months[0].days)
        XCTAssertEqual(monday.months[1].days, sunday.months[1].days)
    }

    func testOnlyFirstWeekdayIsReadFromTheCalendar() throws {
        let group: GroupInfo = makeGroup(testDay: 3)
        let monday: Layout = try layout(group, kept: [0, 2], firstWeekday: 2)
        let tokyo: [CalendarMonth] = StreakCalendar.months(group: group, summary: monday.summary, standing: monday.standing,
                                                           calendar: calendar(firstWeekday: 2, timeZoneID: "Asia/Tokyo"))
        XCTAssertEqual(tokyo, monday.months)
    }

    // MARK: - States

    func testStatesAcrossTheMonthBoundary() throws {
        let group: GroupInfo = makeGroup(testDay: 3)
        let l: Layout = try layout(group, kept: [0, 2])
        let dec: CalendarMonth = l.months[0]
        let jan: CalendarMonth = l.months[1]

        for day in dec.days.prefix(30) {
            XCTAssertEqual(day.state, .outside, "Dec \(day.dayNumber)")
        }
        XCTAssertEqual(dec.days[30].state, .kept)
        XCTAssertEqual(dec.days[30].date, date(1_767_157_200))       // 2025-12-31 00:00 EST
        XCTAssertEqual(dec.days[30].date, DayClock.start(ofDay: 0, group: group))
        XCTAssertEqual(dec.days[0].groupDay, -30)
        XCTAssertEqual(dec.days[30].groupDay, 0)
        XCTAssertEqual(jan.days[2].groupDay, 3)
        XCTAssertEqual(jan.days[0].state, .missed)
        XCTAssertEqual(jan.days[1].state, .kept)
        XCTAssertEqual(jan.days[2].state, .todayOpen)
        XCTAssertEqual(jan.days[2].date, date(1_767_416_400))        // 2026-01-03 00:00 EST
        for day in jan.days[3...] {
            XCTAssertEqual(day.state, .upcoming, "Jan \(day.dayNumber)")
        }

        // Streak 1, begun on Jan 2; no end, so no flag.
        XCTAssertEqual(l.standing.streak, 1)
        XCTAssertTrue(jan.days[1].isStreakStart)
        XCTAssertEqual(countDays(l.months) { (d: CalendarDay) -> Bool in return d.isStreakStart }, 1)
        XCTAssertEqual(countDays(l.months) { (d: CalendarDay) -> Bool in return d.isFinal }, 0)
    }

    func testRealGroupFollowsTheClock() throws {
        let now: Date = date(1_767_373_200)   // 2026-01-02 12:00 EST → day 2
        let l: Layout = try layout(makeGroup(isTest: false), kept: [0, 1], now: now)
        XCTAssertEqual(l.summary.currentDay, 2)
        XCTAssertEqual(l.months.count, 2)
        XCTAssertEqual(l.months[0].days[30].state, .kept)
        XCTAssertEqual(l.months[1].days[0].state, .kept)
        XCTAssertEqual(l.months[1].days[1].state, .todayOpen)
        XCTAssertEqual(l.months[1].days[2].state, .upcoming)
        XCTAssertTrue(l.months[0].days[30].isStreakStart)
    }

    func testLateJoinStartsAtYourFirstVowDay() throws {
        // Joined on day 33 (Mon Feb 2); today is day 35 (Wed Feb 4).
        let l: Layout = try layout(makeGroup(testDay: 35), kept: [33], joinedDay: 33)
        XCTAssertEqual(l.standing.history, [DayOutcome.kept, DayOutcome.missed])
        XCTAssertEqual(l.months.count, 1)
        let feb: CalendarMonth = l.months[0]
        XCTAssertEqual(feb.start, date(1_769_922_000))                 // Sun 2026-02-01 00:00 EST
        XCTAssertEqual(feb.leadingBlanks, 0)
        XCTAssertEqual(feb.days.count, 28)
        XCTAssertEqual(feb.days[0].state, .outside)
        XCTAssertEqual(feb.days[1].state, .kept)
        XCTAssertEqual(feb.days[2].state, .missed)
        XCTAssertEqual(feb.days[3].state, .todayOpen)
        XCTAssertEqual(feb.days[4].state, .upcoming)
        XCTAssertEqual(feb.days[27].state, .upcoming)
    }

    // MARK: - Streak start

    func testStreakStart() throws {
        let group: GroupInfo = makeGroup(testDay: 3)

        // Checked in today: 4 days, from day 0.
        let today: Layout = try layout(group, kept: [0, 1, 2, 3])
        XCTAssertEqual(today.standing.streak, 4)
        XCTAssertEqual(StreakCalendar.streakStartDay(summary: today.summary, standing: today.standing), 0)
        XCTAssertEqual(StreakCalendar.streakStartDate(group: group, summary: today.summary, standing: today.standing),
                       date(1_767_157_200))
        XCTAssertTrue(today.months[0].days[30].isStreakStart)
        XCTAssertEqual(today.months[1].days[2].state, .todayKept)

        // Not yet today: the streak still counts through yesterday.
        let notYet: Layout = try layout(group, kept: [0, 1, 2])
        XCTAssertEqual(notYet.standing.streak, 3)
        XCTAssertEqual(StreakCalendar.streakStartDay(summary: notYet.summary, standing: notYet.standing), 0)
        XCTAssertEqual(notYet.months[1].days[2].state, .todayOpen)

        // Kept only today: the streak starts today.
        let onlyToday: Layout = try layout(group, kept: [3])
        XCTAssertEqual(StreakCalendar.streakStartDay(summary: onlyToday.summary, standing: onlyToday.standing), 3)
        XCTAssertTrue(onlyToday.months[1].days[2].isStreakStart)

        // No streak.
        let none: Layout = try layout(group, kept: [0])
        XCTAssertEqual(none.standing.streak, 0)
        XCTAssertNil(StreakCalendar.streakStartDay(summary: none.summary, standing: none.standing))
        XCTAssertNil(StreakCalendar.streakStartDate(group: group, summary: none.summary, standing: none.standing))
        XCTAssertEqual(countDays(none.months) { (d: CalendarDay) -> Bool in return d.isStreakStart }, 0)
    }

    // MARK: - End date

    func testFinalDayFlagAndUpcomingDays() throws {
        // Final day 40 = Mon Feb 9; today is day 3 (Jan 3).
        let group: GroupInfo = makeGroup(testDay: 3, endDay: 40)
        let l: Layout = try layout(group, kept: [0, 2])
        XCTAssertEqual(l.months.count, 3)
        let jan: CalendarMonth = l.months[1]
        let feb: CalendarMonth = l.months[2]
        XCTAssertEqual(feb.start, date(1_769_922_000))
        XCTAssertEqual(feb.leadingBlanks, 0)
        XCTAssertEqual(feb.days.count, 28)
        for day in jan.days[3...] {
            XCTAssertEqual(day.state, .upcoming, "Jan \(day.dayNumber)")
        }
        for day in feb.days.prefix(9) {
            XCTAssertEqual(day.state, .upcoming, "Feb \(day.dayNumber)")
        }
        for day in feb.days[9...] {
            XCTAssertEqual(day.state, .outside, "Feb \(day.dayNumber)")
        }
        XCTAssertTrue(feb.days[8].isFinal)
        XCTAssertEqual(feb.days[8].date, date(1_770_613_200))         // 2026-02-09 00:00 EST
        XCTAssertEqual(EndDate.finalDate(group), feb.days[8].date)
        XCTAssertEqual(countDays(l.months) { (d: CalendarDay) -> Bool in return d.isFinal }, 1)

        let monday: Layout = try layout(group, kept: [0, 2], firstWeekday: 2)
        XCTAssertEqual(monday.months[2].leadingBlanks, 6)
    }

    func testFinalDayInsideTheCurrentMonth() throws {
        // Final day 5 = Jan 5; today is day 3.
        let l: Layout = try layout(makeGroup(testDay: 3, endDay: 5), kept: [0, 1, 2])
        XCTAssertEqual(l.months.count, 2)
        let jan: CalendarMonth = l.months[1]
        XCTAssertEqual(jan.days[2].state, .todayOpen)
        XCTAssertEqual(jan.days[3].state, .upcoming)
        XCTAssertEqual(jan.days[4].state, .upcoming)
        XCTAssertTrue(jan.days[4].isFinal)
        for day in jan.days[5...] {
            XCTAssertEqual(day.state, .outside, "Jan \(day.dayNumber)")
            XCTAssertFalse(day.isFinal)
        }
    }

    func testFinishedVow() throws {
        // Final day 2 (Jan 2); the clock is at day 5. Check-ins on days 3 and 4 don't count.
        let l: Layout = try layout(makeGroup(testDay: 5, endDay: 2), kept: [0, 1, 2, 3, 4])
        XCTAssertTrue(l.summary.isFinished)
        XCTAssertEqual(l.months.count, 2)
        let dec: CalendarMonth = l.months[0]
        let jan: CalendarMonth = l.months[1]
        XCTAssertEqual(dec.days[30].state, .kept)
        XCTAssertEqual(jan.days[0].state, .kept)
        XCTAssertEqual(jan.days[1].state, .kept)
        XCTAssertTrue(jan.days[1].isFinal)
        for day in jan.days[2...] {
            XCTAssertEqual(day.state, .outside, "Jan \(day.dayNumber)")
        }
        let open: Int = countDays(l.months) { (d: CalendarDay) -> Bool in
            return d.state == .todayOpen || d.state == .todayKept || d.state == .upcoming
        }
        XCTAssertEqual(open, 0)
        XCTAssertEqual(l.standing.streak, 3)
        XCTAssertEqual(StreakCalendar.streakStartDay(summary: l.summary, standing: l.standing), 0)
        XCTAssertTrue(dec.days[30].isStreakStart)
    }

    func testFinishedVowEndsWithTheFinalDaysMonth() throws {
        // Final day 31 = Sat Jan 31; the clock is in February, but February is not shown.
        let l: Layout = try layout(makeGroup(testDay: 40, endDay: 31), kept: [30, 31])
        XCTAssertTrue(l.summary.isFinished)
        XCTAssertEqual(l.months.count, 2)
        let jan: CalendarMonth = l.months[1]
        XCTAssertEqual(jan.days[29].state, .kept)
        XCTAssertEqual(jan.days[30].state, .kept)
        XCTAssertTrue(jan.days[30].isFinal)
        XCTAssertTrue(jan.days[29].isStreakStart)
        XCTAssertEqual(jan.days[28].state, .missed)
    }

    // MARK: - DST

    func testMonthsStepByCalendarDaysAcrossDST() throws {
        // Created Sun 2026-03-01 12:00 EST; clocks spring forward on Mar 8. Today is day 10 (Mar 11).
        let spring: GroupInfo = makeGroup(testDay: 10, createdAt: date(1_772_384_400))
        let l: Layout = try layout(spring, kept: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(l.months.count, 1)
        let march: CalendarMonth = l.months[0]
        XCTAssertEqual(march.start, date(1_772_341_200))               // 2026-03-01 00:00 EST
        XCTAssertEqual(march.leadingBlanks, 0)
        XCTAssertEqual(march.days.count, 31)
        for i in 0..<31 {
            XCTAssertEqual(march.days[i].dayNumber, i + 1)
            XCTAssertEqual(march.days[i].date, DayClock.start(ofDay: i, group: spring), "Mar \(i + 1)")
        }
        XCTAssertEqual(march.days[7].date, date(1_772_946_000))        // Mar 8 00:00 EST
        XCTAssertEqual(march.days[8].date, date(1_773_028_800))        // Mar 9 00:00 EDT
        XCTAssertEqual(march.days[8].date.timeIntervalSince(march.days[7].date), 82_800, accuracy: 1e-9)
        for i in 0..<10 {
            XCTAssertEqual(march.days[i].state, .kept, "Mar \(i + 1)")
        }
        XCTAssertEqual(march.days[10].state, .todayOpen)
        XCTAssertEqual(march.days[30].state, .upcoming)
        XCTAssertTrue(march.days[0].isStreakStart)

        // Created Sat 2026-10-31 12:00 EDT; clocks fall back on Nov 1. Today is day 2 (Nov 2).
        let fall: GroupInfo = makeGroup(testDay: 2, createdAt: date(1_793_462_400))
        let f: Layout = try layout(fall, kept: [0, 1])
        XCTAssertEqual(f.months.count, 2)
        XCTAssertEqual(f.months[0].leadingBlanks, 4)                   // Thu Oct 1, weeks from Sunday
        XCTAssertEqual(f.months[0].days[30].state, .kept)              // Oct 31
        let november: CalendarMonth = f.months[1]
        XCTAssertEqual(november.start, date(1_793_505_600))            // Nov 1 00:00 EDT
        XCTAssertEqual(november.days[1].date, date(1_793_595_600))     // Nov 2 00:00 EST
        XCTAssertEqual(november.days[1].date.timeIntervalSince(november.days[0].date), 90_000, accuracy: 1e-9)
        XCTAssertEqual(november.days[0].state, .kept)
        XCTAssertEqual(november.days[1].state, .todayOpen)
        XCTAssertEqual(november.days.count, 30)
    }
}
