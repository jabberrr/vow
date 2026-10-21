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
        let span: CalendarSpan
        /// Every month of the span, oldest first.
        let months: [CalendarMonth]
    }

    /// Settles a group of "me" (kept on `kept` days, excused on `excused` days) and lays out every month of
    /// its calendar. With `overruled` days, Maya joins too and votes down your claims on them.
    private func layout(_ group: GroupInfo, kept: [Int], excused: [Int] = [], overruled: [Int] = [],
                        joinedDay: Int = 0, firstWeekday: Int = 1, now: Date? = nil) throws -> Layout {
        var members: [MemberInfo] = [MemberInfo(userID: "me", displayName: "Ari", vow: "I will read",
                                                joinedDay: joinedDay, joinedEpoch: 0, leftDay: nil)]
        var checkIns: [CheckInInfo] = []
        for day in kept {
            checkIns.append(CheckInInfo(userID: "me", day: day, epoch: 0, serverDate: nil))
        }
        var excuses: [ExcuseInfo] = []
        for day in excused {
            excuses.append(ExcuseInfo(userID: "me", day: day, epoch: 0, text: "Sick", serverDate: nil))
        }
        var votes: [VoteInfo] = []
        if !overruled.isEmpty {
            members.append(MemberInfo(userID: "maya", displayName: "Maya", vow: "I will run", joinedDay: 0,
                                      joinedEpoch: 0, leftDay: nil))
        }
        for day in overruled {
            votes.append(VoteInfo(voterID: "maya", subjectID: "me", day: day, epoch: 0, counts: false, castDay: day,
                                  serverDate: nil))
        }
        let snapshot: GroupSnapshot = GroupSnapshot(group: group, members: members, checkIns: checkIns, fetchedAt: created,
                                                    excuses: excuses, votes: votes)
        let summary: GroupSummary = Settlement.summarize(snapshot, viewerID: "me", now: now ?? anyNow)
        let standing: MemberStanding = try XCTUnwrap(summary.viewer)
        let span: CalendarSpan = try XCTUnwrap(CalendarSpan(group: group, summary: summary, standing: standing,
                                                            calendar: calendar(firstWeekday: firstWeekday),
                                                            now: now ?? anyNow))
        var months: [CalendarMonth] = []
        for index in 0..<span.count {
            let month: CalendarMonth = try XCTUnwrap(span.month(at: index), "month \(index)")
            months.append(month)
        }
        return Layout(summary: summary, standing: standing, span: span, months: months)
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

    private func joinsPrevious(_ days: ArraySlice<CalendarDay>) -> [Bool] {
        return days.map { (d: CalendarDay) -> Bool in return d.joinsPrevious }
    }

    private func joinsNext(_ days: ArraySlice<CalendarDay>) -> [Bool] {
        return days.map { (d: CalendarDay) -> Bool in return d.joinsNext }
    }

    // MARK: - Span

    func testSpanRunsFromTheGroupsMonthToAYearAhead() throws {
        // Created Mon 2025-11-10 12:00 EST; now is Fri 2025-12-05 12:00 EST (day 25).
        let group: GroupInfo = makeGroup(isTest: false, createdAt: date(1_762_794_000))
        let l: Layout = try layout(group, kept: [0, 1], now: date(1_764_954_000))
        XCTAssertEqual(l.summary.currentDay, 25)

        // Back to November (the group's month), not October; ahead to December 2026, not January 2027.
        XCTAssertEqual(l.span.count, 14)
        XCTAssertEqual(l.span.home, 1)
        XCTAssertEqual(l.months[0].start, date(1_761_969_600))         // Sat 2025-11-01 00:00 EDT
        XCTAssertEqual(l.months[1].start, date(1_764_565_200))         // Mon 2025-12-01 00:00 EST
        XCTAssertEqual(l.months[13].start, date(1_796_101_200))        // Tue 2026-12-01 00:00 EST
        XCTAssertNil(l.span.month(at: -1))
        XCTAssertNil(l.span.month(at: 14))

        // Nov 1–9 come before the group began.
        let november: CalendarMonth = l.months[0]
        for day in november.days.prefix(9) {
            XCTAssertEqual(day.state, .outside, "Nov \(day.dayNumber)")
            XCTAssertLessThan(day.groupDay, 0)
        }
        XCTAssertEqual(november.days[9].groupDay, 0)
        XCTAssertEqual(november.days[9].state, .kept)
        XCTAssertEqual(november.days[11].state, .missed)
        XCTAssertEqual(l.months[1].days[4].state, .todayOpen)
    }

    func testMonthSpanAndLeadingBlanks() throws {
        let sunday: Layout = try layout(makeGroup(testDay: 3), kept: [0, 2], firstWeekday: 1)
        // December 2025 (the group's month) through January 2027 (today's month + 12).
        XCTAssertEqual(sunday.span.count, 14)
        XCTAssertEqual(sunday.span.home, 1)
        XCTAssertEqual(sunday.months[0].start, date(1_764_565_200))   // Mon 2025-12-01 00:00 EST
        XCTAssertEqual(sunday.months[1].start, date(1_767_243_600))   // Thu 2026-01-01 00:00 EST
        XCTAssertEqual(sunday.months[13].start, date(1_798_779_600))  // Fri 2027-01-01 00:00 EST
        XCTAssertEqual(sunday.months[0].id, sunday.months[0].start)
        XCTAssertEqual(sunday.months[0].leadingBlanks, 1)
        XCTAssertEqual(sunday.months[1].leadingBlanks, 4)
        XCTAssertEqual(sunday.months[13].leadingBlanks, 5)
        XCTAssertEqual(sunday.months[0].days.count, 31)
        XCTAssertEqual(sunday.months[1].days.count, 31)
        XCTAssertEqual(sunday.months[0].days.first?.dayNumber, 1)
        XCTAssertEqual(sunday.months[0].days.last?.dayNumber, 31)
        XCTAssertEqual(sunday.months[0].days.first?.date, sunday.months[0].start)

        // No runs here (days 0 and 2 kept, 1 missed), so the joins agree whatever the first weekday.
        let monday: Layout = try layout(makeGroup(testDay: 3), kept: [0, 2], firstWeekday: 2)
        XCTAssertEqual(monday.span.count, 14)
        XCTAssertEqual(monday.months[0].leadingBlanks, 0)
        XCTAssertEqual(monday.months[1].leadingBlanks, 3)
        XCTAssertEqual(monday.months[0].days, sunday.months[0].days)
        XCTAssertEqual(monday.months[1].days, sunday.months[1].days)
    }

    func testOnlyFirstWeekdayIsReadFromTheCalendar() throws {
        let group: GroupInfo = makeGroup(testDay: 3)
        let monday: Layout = try layout(group, kept: [0, 1, 2], firstWeekday: 2)
        let tokyo: CalendarSpan = try XCTUnwrap(CalendarSpan(group: group, summary: monday.summary,
                                                             standing: monday.standing,
                                                             calendar: calendar(firstWeekday: 2, timeZoneID: "Asia/Tokyo"),
                                                             now: anyNow))
        XCTAssertEqual(tokyo.count, monday.span.count)
        XCTAssertEqual(tokyo.home, monday.span.home)
        for index in 0..<tokyo.count {
            XCTAssertEqual(tokyo.month(at: index), monday.months[index], "month \(index)")
        }
    }

    func testEndMonthBeyondAYearAhead() throws {
        // Final day 500 = Sat 2027-05-15, past January 2027 (today's month + 12): the span runs to May.
        let l: Layout = try layout(makeGroup(testDay: 3, endDay: 500), kept: [0, 1, 2])
        XCTAssertEqual(l.span.count, 18)
        XCTAssertEqual(l.span.home, 1)
        let may: CalendarMonth = l.months[17]
        XCTAssertEqual(may.start, date(1_809_144_000))                  // 2027-05-01 00:00 EDT
        XCTAssertTrue(may.days[14].isFinal)
        XCTAssertEqual(may.days[14].groupDay, 500)
        XCTAssertEqual(may.days[14].state, .upcoming)
        for day in may.days[15...] {
            XCTAssertEqual(day.state, .outside, "May \(day.dayNumber)")
        }
        XCTAssertEqual(countDays(l.months) { (d: CalendarDay) -> Bool in return d.isFinal }, 1)
    }

    func testFinishedRealVowStillReachesAYearPastToday() throws {
        // Final day 10 (Sat Jan 10); now is Fri 2026-04-10 12:00 EDT (day 100). The summary stops at day 11,
        // the clock doesn't: the span runs to April 2027 and opens on January, the final day's month.
        let l: Layout = try layout(makeGroup(isTest: false, endDay: 10), kept: [0, 1, 2], now: date(1_775_836_800))
        XCTAssertTrue(l.summary.isFinished)
        XCTAssertEqual(l.summary.currentDay, 11)
        XCTAssertEqual(l.span.count, 17)
        XCTAssertEqual(l.span.home, 1)
        XCTAssertEqual(l.months[16].start, date(1_806_552_000))         // 2027-04-01 00:00 EDT
        XCTAssertTrue(l.months[1].days[9].isFinal)
        XCTAssertEqual(l.months[1].days[9].state, .missed)
        for month in l.months[2...] {
            for day in month.days {
                XCTAssertEqual(day.state, .outside)
            }
        }
        let open: Int = countDays(l.months) { (d: CalendarDay) -> Bool in
            return d.state == .todayOpen || d.state == .todayKept || d.state == .upcoming
        }
        XCTAssertEqual(open, 0)
    }

    func testSpanIsCapped() throws {
        // Day 40,000 is in July 2135, more than maxMonths after December 2025. Built by hand: settling
        // 40,000 days would only slow the test down.
        let group: GroupInfo = makeGroup(testDay: 40_000)
        let me: MemberStanding = MemberStanding(userID: "me", displayName: "Ari", vow: "I will read", isActive: true,
                                                net: 0, streak: 0, bestStreak: 0, history: [],
                                                checkedInToday: false, missedYesterday: false)
        let summary: GroupSummary = GroupSummary(currentDay: 40_000, cycle: 1_334, dayInCycle: 11, glyphNumber: 40_001,
                                                 pot: 0, totalForfeited: 0, standings: [me], ledger: [], viewer: me)
        let span: CalendarSpan = try XCTUnwrap(CalendarSpan(group: group, summary: summary, standing: me,
                                                            calendar: calendar(firstWeekday: 1), now: anyNow))
        XCTAssertEqual(span.count, StreakCalendar.maxMonths)
        XCTAssertEqual(span.home, StreakCalendar.maxMonths - 1)
        XCTAssertNotNil(span.month(at: StreakCalendar.maxMonths - 1))
        XCTAssertNil(span.month(at: StreakCalendar.maxMonths))
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

        // No end: every day of the months ahead is to come, and there's no flag.
        for month in l.months[2...] {
            for day in month.days {
                XCTAssertEqual(day.state, .upcoming)
            }
        }
        XCTAssertEqual(l.months[13].days[30].groupDay, 396)          // 2027-01-31
        XCTAssertEqual(countDays(l.months) { (d: CalendarDay) -> Bool in return d.isFinal }, 0)
    }

    func testRealGroupFollowsTheClock() throws {
        let now: Date = date(1_767_373_200)   // 2026-01-02 12:00 EST → day 2
        let l: Layout = try layout(makeGroup(isTest: false), kept: [0, 1], now: now)
        XCTAssertEqual(l.summary.currentDay, 2)
        XCTAssertEqual(l.span.count, 14)
        XCTAssertEqual(l.span.home, 1)
        XCTAssertEqual(l.months[0].days[30].state, .kept)
        XCTAssertEqual(l.months[1].days[0].state, .kept)
        XCTAssertEqual(l.months[1].days[1].state, .todayOpen)
        XCTAssertEqual(l.months[1].days[2].state, .upcoming)
    }

    func testLateJoinStartsAtYourFirstVowDay() throws {
        // Joined on day 33 (Mon Feb 2); today is day 35 (Wed Feb 4). The span still starts with the
        // group's month, but nothing before your first vow day is yours.
        let l: Layout = try layout(makeGroup(testDay: 35), kept: [33], joinedDay: 33)
        XCTAssertEqual(l.standing.history, [DayOutcome.kept, DayOutcome.missed])
        XCTAssertEqual(l.span.count, 15)
        XCTAssertEqual(l.span.home, 2)
        XCTAssertEqual(countDays(Array(l.months[0...1])) { (d: CalendarDay) -> Bool in return d.state != .outside }, 0)
        let feb: CalendarMonth = l.months[2]
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

    // MARK: - Runs

    func testRunsJoinWithinAWeekRow() throws {
        // Today is day 9 (Fri Jan 9), kept; day 6 (Tue Jan 6) missed. Weeks from Sunday: Jan 1 is in
        // column 4, Sat Jan 3 ends the first row and Sun Jan 4 starts the second.
        let sunday: Layout = try layout(makeGroup(testDay: 9), kept: [0, 1, 2, 3, 4, 5, 7, 8, 9])
        let dec31: CalendarDay = sunday.months[0].days[30]
        XCTAssertEqual(dec31.state, .kept)
        XCTAssertFalse(dec31.joinsPrevious)                          // Dec 30 is before the group
        XCTAssertFalse(dec31.joinsNext)                              // Jan 1 is in the next month's grid
        let jan: CalendarMonth = sunday.months[1]
        XCTAssertEqual(jan.days[8].state, .todayKept)
        XCTAssertEqual(joinsPrevious(jan.days[0..<10]), [false, true, true, false, true, false, false, true, true, false])
        XCTAssertEqual(joinsNext(jan.days[0..<10]), [true, true, false, true, false, false, true, true, false, false])
        XCTAssertEqual(countDays(sunday.months) { (d: CalendarDay) -> Bool in return d.joinsPrevious }, 5)
        XCTAssertEqual(countDays(sunday.months) { (d: CalendarDay) -> Bool in return d.joinsNext }, 5)

        // Weeks from Monday: Jan 1 is in column 3, Sun Jan 4 ends the first row and Mon Jan 5 starts the second.
        let monday: Layout = try layout(makeGroup(testDay: 9), kept: [0, 1, 2, 3, 4, 5, 7, 8, 9], firstWeekday: 2)
        let janMonday: CalendarMonth = monday.months[1]
        XCTAssertEqual(joinsPrevious(janMonday.days[0..<10]), [false, true, true, true, false, false, false, true, true, false])
        XCTAssertEqual(joinsNext(janMonday.days[0..<10]), [true, true, true, false, false, false, true, true, false, false])
    }

    func testTodayJoinsTheRunOnlyOnceKept() throws {
        let open: Layout = try layout(makeGroup(testDay: 9), kept: [7, 8])
        let jan: CalendarMonth = open.months[1]
        XCTAssertEqual(jan.days[8].state, .todayOpen)
        XCTAssertTrue(jan.days[7].joinsPrevious)
        XCTAssertFalse(jan.days[7].joinsNext)
        XCTAssertFalse(jan.days[8].joinsPrevious)
        XCTAssertFalse(jan.days[8].joinsNext)

        let kept: Layout = try layout(makeGroup(testDay: 9), kept: [7, 8, 9])
        XCTAssertTrue(kept.months[1].days[7].joinsNext)
        XCTAssertTrue(kept.months[1].days[8].joinsPrevious)
        XCTAssertFalse(kept.months[1].days[8].joinsNext)              // Jan 10 is to come
    }

    // MARK: - Excuses and votes

    func testExcusedDaysBreakTheBandButNotTheStreak() throws {
        // Today is day 9 (Fri Jan 9), kept; day 7 (Wed Jan 7) excused. Jan 4...10 share a week row.
        let l: Layout = try layout(makeGroup(testDay: 9), kept: [5, 6, 8, 9], excused: [7])
        let jan: CalendarMonth = l.months[1]
        XCTAssertEqual(jan.days[4].state, .kept)
        XCTAssertEqual(jan.days[5].state, .kept)
        XCTAssertEqual(jan.days[6].state, .excused)
        XCTAssertEqual(jan.days[7].state, .kept)
        XCTAssertEqual(jan.days[8].state, .todayKept)
        XCTAssertFalse(CalendarDayState.excused.isKept)
        XCTAssertEqual(joinsPrevious(jan.days[4..<9]), [false, true, false, false, true])
        XCTAssertEqual(joinsNext(jan.days[4..<9]), [true, false, false, true, false])

        // The streak runs through the excused day: Jan 5, 6, 8 and today.
        XCTAssertEqual(l.standing.streak, 4)
        XCTAssertEqual(StreakCalendar.streakStartDay(summary: l.summary, standing: l.standing), 5)

        // Excused right up to today, which is still open: the streak began on day 5 all the same.
        let open: Layout = try layout(makeGroup(testDay: 9), kept: [5, 6], excused: [7, 8])
        XCTAssertEqual(open.months[1].days[8].state, .todayOpen)
        XCTAssertEqual(open.standing.streak, 2)
        XCTAssertEqual(StreakCalendar.streakStartDay(summary: open.summary, standing: open.standing), 5)
    }

    func testTodayExcusedAndOverruled() throws {
        let group: GroupInfo = makeGroup(testDay: 3)

        let excused: Layout = try layout(group, kept: [0, 1, 2], excused: [3])
        XCTAssertEqual(excused.months[1].days[2].state, .todayExcused)
        XCTAssertFalse(excused.months[1].days[1].joinsNext)
        XCTAssertEqual(excused.standing.streak, 3)

        // Your check-in today is overruled: it doesn't join the run or count toward the streak.
        let overruled: Layout = try layout(group, kept: [0, 1, 2, 3], overruled: [3])
        XCTAssertEqual(overruled.months[1].days[2].state, .todayOverruled)
        XCTAssertFalse(overruled.months[1].days[1].joinsNext)
        XCTAssertEqual(overruled.standing.streak, 3)
        XCTAssertEqual(StreakCalendar.streakStartDay(summary: overruled.summary, standing: overruled.standing), 0)

        let excuseOverruled: Layout = try layout(group, kept: [0, 1, 2], excused: [3], overruled: [3])
        XCTAssertEqual(excuseOverruled.months[1].days[2].state, .todayOverruled)
    }

    func testOverruledDaysAreMissed() throws {
        // Day 1 (Jan 1) checked in and day 2 (Jan 2) excused, both overruled.
        let l: Layout = try layout(makeGroup(testDay: 3), kept: [0, 1], excused: [2], overruled: [1, 2])
        XCTAssertEqual(l.months[0].days[30].state, .kept)
        XCTAssertEqual(l.months[1].days[0].state, .missed)
        XCTAssertEqual(l.months[1].days[1].state, .missed)
        XCTAssertEqual(l.months[1].days[2].state, .todayOpen)
        XCTAssertEqual(l.standing.streak, 0)
        XCTAssertNil(StreakCalendar.streakStartDay(summary: l.summary, standing: l.standing))
    }

    func testWhichStatesAreToday() {
        let today: [CalendarDayState] = [.todayOpen, .todayKept, .todayExcused, .todayOverruled]
        let other: [CalendarDayState] = [.kept, .missed, .excused, .upcoming, .outside]
        for state in today {
            XCTAssertTrue(state.isToday, "\(state)")
        }
        for state in other {
            XCTAssertFalse(state.isToday, "\(state)")
        }
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
        XCTAssertEqual(today.months[1].days[2].state, .todayKept)

        // Not yet today: the streak still counts through yesterday.
        let notYet: Layout = try layout(group, kept: [0, 1, 2])
        XCTAssertEqual(notYet.standing.streak, 3)
        XCTAssertEqual(StreakCalendar.streakStartDay(summary: notYet.summary, standing: notYet.standing), 0)
        XCTAssertEqual(notYet.months[1].days[2].state, .todayOpen)

        // Kept only today: the streak starts today.
        let onlyToday: Layout = try layout(group, kept: [3])
        XCTAssertEqual(StreakCalendar.streakStartDay(summary: onlyToday.summary, standing: onlyToday.standing), 3)

        // No streak.
        let none: Layout = try layout(group, kept: [0])
        XCTAssertEqual(none.standing.streak, 0)
        XCTAssertNil(StreakCalendar.streakStartDay(summary: none.summary, standing: none.standing))
        XCTAssertNil(StreakCalendar.streakStartDate(group: group, summary: none.summary, standing: none.standing))
    }

    // MARK: - End date

    func testFinalDayFlagAndUpcomingDays() throws {
        // Final day 40 = Mon Feb 9; today is day 3 (Jan 3).
        let group: GroupInfo = makeGroup(testDay: 3, endDay: 40)
        let l: Layout = try layout(group, kept: [0, 2])
        XCTAssertEqual(l.span.count, 14)
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
        // The months ahead are after the final day.
        for month in l.months[3...] {
            for day in month.days {
                XCTAssertEqual(day.state, .outside)
            }
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
        XCTAssertEqual(l.span.count, 14)
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
        XCTAssertEqual(l.span.count, 14)
        XCTAssertEqual(l.span.home, 1)
        let dec: CalendarMonth = l.months[0]
        let jan: CalendarMonth = l.months[1]
        XCTAssertEqual(dec.days[30].state, .kept)
        XCTAssertEqual(jan.days[0].state, .kept)
        XCTAssertEqual(jan.days[1].state, .kept)
        XCTAssertTrue(jan.days[1].isFinal)
        XCTAssertTrue(jan.days[0].joinsNext)
        XCTAssertTrue(jan.days[1].joinsPrevious)
        XCTAssertFalse(jan.days[1].joinsNext)
        for day in jan.days[2...] {
            XCTAssertEqual(day.state, .outside, "Jan \(day.dayNumber)")
        }
        let open: Int = countDays(l.months) { (d: CalendarDay) -> Bool in
            return d.state == .todayOpen || d.state == .todayKept || d.state == .upcoming
        }
        XCTAssertEqual(open, 0)
        XCTAssertEqual(l.standing.streak, 3)
        XCTAssertEqual(StreakCalendar.streakStartDay(summary: l.summary, standing: l.standing), 0)
    }

    func testFinishedVowOpensOnTheFinalDaysMonth() throws {
        // Final day 31 = Sat Jan 31; the clock is at day 40 (Feb 9). January opens; February is all outside.
        let l: Layout = try layout(makeGroup(testDay: 40, endDay: 31), kept: [30, 31])
        XCTAssertTrue(l.summary.isFinished)
        XCTAssertEqual(l.span.count, 15)
        XCTAssertEqual(l.span.home, 1)
        let jan: CalendarMonth = l.months[1]
        XCTAssertEqual(jan.days[28].state, .missed)
        XCTAssertEqual(jan.days[29].state, .kept)
        XCTAssertEqual(jan.days[30].state, .kept)
        XCTAssertTrue(jan.days[30].isFinal)
        XCTAssertTrue(jan.days[29].joinsNext)
        XCTAssertTrue(jan.days[30].joinsPrevious)
        XCTAssertEqual(countDays([l.months[2]]) { (d: CalendarDay) -> Bool in return d.state != .outside }, 0)
    }

    // MARK: - DST

    func testMonthsStepByCalendarDaysAcrossDST() throws {
        // Created Sun 2026-03-01 12:00 EST; clocks spring forward on Mar 8. Today is day 10 (Mar 11).
        let spring: GroupInfo = makeGroup(testDay: 10, createdAt: date(1_772_384_400))
        let l: Layout = try layout(spring, kept: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(l.span.count, 13)
        XCTAssertEqual(l.span.home, 0)
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

        // Created Sat 2026-10-31 12:00 EDT; clocks fall back on Nov 1. Today is day 2 (Nov 2).
        let fall: GroupInfo = makeGroup(testDay: 2, createdAt: date(1_793_462_400))
        let f: Layout = try layout(fall, kept: [0, 1])
        XCTAssertEqual(f.span.count, 14)
        XCTAssertEqual(f.span.home, 1)
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
