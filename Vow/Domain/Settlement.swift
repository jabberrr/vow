import Foundation

/// Pure, deterministic settlement of a group from its records. Every device computes the same result.
enum Settlement {
    /// The ledger lists this many days, newest first; every day still settles.
    static let dayCap: Int = 120

    /// A check-in counts on the terms of `isOnTime`.
    static func isValid(_ c: CheckInInfo, group: GroupInfo) -> Bool {
        return isOnTime(day: c.day, epoch: c.epoch, served: c.serverDate, group: group)
    }

    /// An excuse is valid on exactly a check-in's terms.
    static func isValid(_ e: ExcuseInfo, group: GroupInfo) -> Bool {
        return isOnTime(day: e.day, epoch: e.epoch, served: e.serverDate, group: group)
    }

    /// A claim on `day` (a check-in or an excuse) counts if it is in the group's current epoch, not after
    /// the group's final day, and either pending (no server date), in a test group, or landed on its own
    /// day (or within the grace period into the next day).
    static func isOnTime(day: Int, epoch: Int, served: Date?, group: GroupInfo) -> Bool {
        if epoch != group.epoch || day < 0 {
            return false
        }
        if let end: Int = group.endDay, day > end {
            return false
        }
        guard let date: Date = served else {
            return true
        }
        if group.isTest {
            return true
        }
        return DayClock.lands(date, in: day...day, group: group)
    }

    static func summarize(_ snapshot: GroupSnapshot, viewerID: String, now: Date) -> GroupSummary {
        let group: GroupInfo = snapshot.group
        let clockDay: Int = DayClock.currentDay(group, now: now)
        // The settlement horizon. Without an end date (or before it has passed) it is today, the open
        // day. Once the final day has passed it is the day after it: days 0...endDay settle exactly as
        // they would without an end, and nothing happens after them.
        let isFinished: Bool
        let currentDay: Int
        if let end: Int = group.endDay, clockDay > end {
            isFinished = true
            currentDay = max(0, end + 1)
        } else {
            isFinished = false
            currentDay = clockDay
        }
        let stake: Double = Double(group.stake)
        let members: [MemberInfo] = orderedMembers(snapshot.members)

        var keptKeys: Set<String> = []
        for c in snapshot.checkIns {
            if isValid(c, group: group) {
                keptKeys.insert(key(c.userID, c.day))
            }
        }
        var excusedKeys: Set<String> = []
        for e in snapshot.excuses where isValid(e, group: group) {
            excusedKeys.insert(key(e.userID, e.day))
        }
        let claims: Claims = Claims(group: group, checkIns: keptKeys, excuses: excusedKeys,
                                    ballots: Review.Ballots(snapshot.votes, group: group, days: 0...currentDay))

        var nets: [String: Double] = [:]
        var histories: [String: [DayOutcome]] = [:]
        for m in members {
            nets[m.userID] = 0
            histories[m.userID] = []
        }

        var pot: Double = 0
        var totalForfeited: Double = 0
        var days: [LedgerDay] = []   // chronological (oldest first)

        for day in 0...currentDay {
            // A finished vow has no open day: nothing is recorded after its final day.
            if isFinished && day == currentDay {
                break
            }

            // Membership events.
            var joined: [LedgerPerson] = []
            var left: [LedgerPerson] = []
            for m in members {
                if effectiveJoinedDay(m, group: group) == day {
                    joined.append(person(m))
                }
                if let leftDay: Int = m.leftDay, leftDay == day {
                    left.append(person(m))
                }
            }

            // Today is open: nothing settles, and only its joins and leaves are listed.
            if day == currentDay {
                if !joined.isEmpty || !left.isEmpty {
                    days.append(LedgerDay(day: day, isClosed: false, joined: joined, left: left, kept: [], excused: [],
                                          forfeits: [], carriedIn: 0, share: 0, carriedOut: 0))
                }
                break
            }

            // A standing check-in keeps the day and a standing excuse sits it out; no claim, or an
            // overruled one, forfeits the stake.
            let participants: [MemberInfo] = participating(members, day: day, group: group)
            var kept: [LedgerPerson] = []
            var excused: [LedgerPerson] = []
            var forfeits: [Forfeit] = []
            for m in participants {
                let ruling: Ruling? = claims.ruling(m.userID, day: day, participants: participants)
                let outcome: DayOutcome = ruling?.outcome ?? .missed
                histories[m.userID, default: []].append(outcome)
                switch outcome {
                case .kept:
                    kept.append(person(m))
                case .missed:
                    nets[m.userID, default: 0] -= stake
                    forfeits.append(Forfeit(person: person(m), reason: reason(ruling), amount: stake))
                case .excused:
                    excused.append(person(m))
                }
            }

            // The keepers split the carry and the day's forfeits. With no keeper both go on to the next day,
            // so a day everyone sat out leaves the pot untouched.
            let carriedIn: Double = pot
            let lost: Double = stake * Double(forfeits.count)
            pot += lost
            totalForfeited += lost
            var share: Double = 0
            if !kept.isEmpty {
                share = pot / Double(kept.count)
                for p in kept {
                    nets[p.userID, default: 0] += share
                }
                pot = 0
            }

            if !participants.isEmpty || !joined.isEmpty || !left.isEmpty {
                days.append(LedgerDay(day: day, isClosed: true, joined: joined, left: left, kept: kept, excused: excused,
                                      forfeits: forfeits, carriedIn: carriedIn, share: share, carriedOut: pot))
            }
        }

        // Standings: active members only, viewer first, then by name.
        let present: [MemberInfo] = participating(members, day: currentDay, group: group)
        var standings: [MemberStanding] = []
        for m in members where m.leftDay == nil {
            standings.append(standing(for: m,
                                      group: group,
                                      currentDay: currentDay,
                                      net: nets[m.userID] ?? 0,
                                      history: histories[m.userID] ?? [],
                                      claims: claims,
                                      present: present))
        }
        standings.sort { (a: MemberStanding, b: MemberStanding) -> Bool in
            let aViewer: Bool = a.userID == viewerID
            let bViewer: Bool = b.userID == viewerID
            if aViewer != bViewer {
                return aViewer
            }
            return nameLess(a.displayName, a.userID, b.displayName, b.userID)
        }

        var viewer: MemberStanding? = nil
        for s in standings where s.userID == viewerID {
            viewer = s
        }

        return GroupSummary(currentDay: currentDay,
                            cycle: currentDay / 30 + 1,
                            dayInCycle: currentDay % 30 + 1,
                            glyphNumber: currentDay + 1,
                            pot: pot,
                            totalForfeited: totalForfeited,
                            standings: standings,
                            days: Array(days.reversed().prefix(dayCap)),
                            viewer: viewer,
                            endDay: group.endDay,
                            isFinished: isFinished)
    }

    // MARK: - Rules

    /// Members who joined in an older epoch take part from day 0 of the current epoch.
    static func effectiveJoinedDay(_ m: MemberInfo, group: GroupInfo) -> Int {
        return m.joinedEpoch == group.epoch ? m.joinedDay : 0
    }

    static func participates(_ m: MemberInfo, day: Int, group: GroupInfo) -> Bool {
        if day < effectiveJoinedDay(m, group: group) {
            return false
        }
        if let left: Int = m.leftDay, day >= left {
            return false
        }
        return true
    }

    /// The members taking part on `day`, in the given order.
    static func participating(_ members: [MemberInfo], day: Int, group: GroupInfo) -> [MemberInfo] {
        var out: [MemberInfo] = []
        for m in members where participates(m, day: day, group: group) {
            out.append(m)
        }
        return out
    }

    /// Deduplicated by userID (first wins), sorted by name for deterministic ledger order.
    static func orderedMembers(_ input: [MemberInfo]) -> [MemberInfo] {
        var seen: Set<String> = []
        var out: [MemberInfo] = []
        for m in input {
            if seen.contains(m.userID) {
                continue
            }
            seen.insert(m.userID)
            out.append(m)
        }
        out.sort { (a: MemberInfo, b: MemberInfo) -> Bool in
            return nameLess(a.displayName, a.userID, b.displayName, b.userID)
        }
        return out
    }

    // MARK: - Helpers

    private static func key(_ userID: String, _ day: Int) -> String {
        return "\(day)|\(userID)"
    }

    private static func person(_ m: MemberInfo) -> LedgerPerson {
        return LedgerPerson(userID: m.userID, name: m.displayName)
    }

    /// Why a miss cost the stake: no claim, or the claim the group overruled.
    private static func reason(_ ruling: Ruling?) -> Forfeit.Reason {
        guard let found: Ruling = ruling else { return .missed }
        return found.claim == .checkIn ? .checkInOverruled : .excuseOverruled
    }

    private static func nameLess(_ aName: String, _ aID: String, _ bName: String, _ bID: String) -> Bool {
        let a: String = aName.lowercased()
        let b: String = bName.lowercased()
        if a != b {
            return a < b
        }
        return aID < bID
    }

    /// `present`: the members taking part on `currentDay`, who vote on its claims.
    private static func standing(for m: MemberInfo,
                                 group: GroupInfo,
                                 currentDay: Int,
                                 net: Double,
                                 history: [DayOutcome],
                                 claims: Claims,
                                 present: [MemberInfo]) -> MemberStanding {
        let checkedInToday: Bool = claims.checkIns.contains(key(m.userID, currentDay))
        let excusedToday: Bool = !checkedInToday && claims.excuses.contains(key(m.userID, currentDay))
        var todayOverruled: Bool = false
        if present.contains(where: { (p: MemberInfo) -> Bool in p.userID == m.userID }) {
            todayOverruled = claims.ruling(m.userID, day: currentDay, participants: present)?.overruled ?? false
        }

        // Excused days neither break nor extend a run.
        var trailing: Int = 0
        for outcome in history.reversed() where outcome != .excused {
            if outcome == .missed {
                break
            }
            trailing += 1
        }
        let streak: Int = trailing + (checkedInToday && !todayOverruled ? 1 : 0)

        var best: Int = 0
        var run: Int = 0
        for outcome in history {
            switch outcome {
            case .kept:
                run += 1
                best = max(best, run)
            case .missed:
                run = 0
            case .excused:
                break
            }
        }
        best = max(best, streak)

        var missedYesterday: Bool = false
        if currentDay >= 1 && participates(m, day: currentDay - 1, group: group) {
            // History ends with yesterday whenever you took part in it.
            missedYesterday = history.last == .missed
        }

        return MemberStanding(userID: m.userID,
                              displayName: m.displayName,
                              vow: m.vow,
                              isActive: m.leftDay == nil,
                              net: net,
                              streak: streak,
                              bestStreak: best,
                              history: history,
                              checkedInToday: checkedInToday,
                              missedYesterday: missedYesterday,
                              excusedToday: excusedToday,
                              todayOverruled: todayOverruled)
    }

    // MARK: - Claims

    private enum Claim {
        case checkIn, excuse
    }

    /// A claim and the group's verdict on it so far.
    private struct Ruling {
        let claim: Claim
        let overruled: Bool

        var outcome: DayOutcome {
            if overruled {
                return .missed
            }
            return claim == .checkIn ? .kept : .excused
        }
    }

    /// One pass's valid check-ins and excuses by (userID, day), and the votes on them: indexed once, read
    /// per member and day.
    private struct Claims {
        let group: GroupInfo
        let checkIns: Set<String>
        let excuses: Set<String>
        let ballots: Review.Ballots

        /// `userID`'s claim on `day` (a check-in wins over an excuse) and its verdict; nil without one.
        /// `participants`: everyone taking part that day.
        func ruling(_ userID: String, day: Int, participants: [MemberInfo]) -> Ruling? {
            let k: String = Settlement.key(userID, day)
            let claim: Claim
            if checkIns.contains(k) {
                claim = .checkIn
            } else if excuses.contains(k) {
                claim = .excuse
            } else {
                return nil
            }
            let verdict: Review.Verdict = Review.verdict(subject: userID, day: day, isExcuse: claim == .excuse,
                                                         participants: participants,
                                                         rule: Review.rule(forDay: day, group: group),
                                                         ballots: ballots)
            return Ruling(claim: claim, overruled: verdict.overruled)
        }
    }
}
