import Foundation

/// Pure, deterministic settlement of a group from its records. Every device computes the same result.
enum Settlement {
    static let ledgerCap: Int = 120

    /// A check-in counts if it is in the group's current epoch and either pending (no server date),
    /// in a test group, or landed on its own day (or within the grace period into the next day).
    static func isValid(_ c: CheckInInfo, group: GroupInfo) -> Bool {
        if c.epoch != group.epoch || c.day < 0 {
            return false
        }
        guard let served: Date = c.serverDate else {
            return true
        }
        if group.isTest {
            return true
        }
        let servedDay: Int = DayClock.dayIndex(of: served, start: group.createdAt, timeZoneID: group.timeZoneID)
        if servedDay == c.day {
            return true
        }
        if servedDay == c.day + 1 {
            guard let boundary: Date = DayClock.start(ofDay: c.day + 1, group: group) else {
                return false
            }
            return served < boundary.addingTimeInterval(DayClock.graceSeconds)
        }
        return false
    }

    static func summarize(_ snapshot: GroupSnapshot, viewerID: String, now: Date) -> GroupSummary {
        let group: GroupInfo = snapshot.group
        let currentDay: Int = DayClock.currentDay(group, now: now)
        let stake: Double = Double(group.stake)
        let members: [MemberInfo] = orderedMembers(snapshot.members)

        var keptKeys: Set<String> = []
        for c in snapshot.checkIns {
            if isValid(c, group: group) {
                keptKeys.insert(key(c.userID, c.day))
            }
        }

        var nets: [String: Double] = [:]
        var histories: [String: [DayOutcome]] = [:]
        for m in members {
            nets[m.userID] = 0
            histories[m.userID] = []
        }

        var pot: Double = 0
        var totalForfeited: Double = 0
        var lines: [LedgerLine] = []   // chronological (oldest first)

        for day in 0...currentDay {
            let dayLabel: String = "Day \(day + 1) · "

            // Membership events.
            for m in members {
                let name: String = displayName(m, viewerID: viewerID)
                if effectiveJoinedDay(m, group: group) == day {
                    lines.append(LedgerLine(id: "d\(day)-joined-\(m.userID)", day: day, kind: .joined,
                                            text: "\(dayLabel)\(name) joined", amount: nil))
                }
                if let left: Int = m.leftDay, left == day {
                    lines.append(LedgerLine(id: "d\(day)-left-\(m.userID)", day: day, kind: .info,
                                            text: "\(dayLabel)\(name) left", amount: nil))
                }
            }

            // Today is open: nothing settles.
            if day == currentDay {
                break
            }

            var keepers: [MemberInfo] = []
            var missers: [MemberInfo] = []
            for m in members {
                if !participates(m, day: day, group: group) {
                    continue
                }
                if keptKeys.contains(key(m.userID, day)) {
                    keepers.append(m)
                    histories[m.userID, default: []].append(.kept)
                } else {
                    missers.append(m)
                    histories[m.userID, default: []].append(.missed)
                }
            }
            if keepers.isEmpty && missers.isEmpty {
                continue
            }

            let forfeits: Double = stake * Double(missers.count)
            pot += forfeits
            totalForfeited += forfeits

            // Viewer's own line.
            var viewerKept: Bool = false
            for m in keepers where m.userID == viewerID {
                viewerKept = true
                lines.append(LedgerLine(id: "d\(day)-kept-\(m.userID)", day: day, kind: .kept,
                                        text: "\(dayLabel)You kept", amount: nil))
            }
            for m in missers where m.userID == viewerID {
                lines.append(LedgerLine(id: "d\(day)-missed-\(m.userID)", day: day, kind: .missed,
                                        text: "\(dayLabel)You missed · \(Points.format(-stake))",
                                        amount: -stake))
            }

            // Everyone else's forfeits.
            for m in missers {
                nets[m.userID, default: 0] -= stake
                if m.userID == viewerID {
                    continue
                }
                lines.append(LedgerLine(id: "d\(day)-forfeit-\(m.userID)", day: day, kind: .forfeit,
                                        text: "\(dayLabel)\(displayName(m, viewerID: viewerID)) missed · \(Points.format(-stake))",
                                        amount: nil))
            }

            if keepers.isEmpty {
                lines.append(LedgerLine(id: "d\(day)-carry", day: day, kind: .carry,
                                        text: "\(dayLabel)Nobody kept · pot carries \(Points.format(pot))",
                                        amount: nil))
            } else {
                if pot > 0 {
                    let share: Double = pot / Double(keepers.count)
                    for m in keepers {
                        nets[m.userID, default: 0] += share
                    }
                    let ways: String = keepers.count == 1 ? "1 way" : "\(keepers.count) ways"
                    lines.append(LedgerLine(id: "d\(day)-split", day: day, kind: .split,
                                            text: "\(dayLabel)Pot split \(ways) · \(Points.format(share, signed: true)) each",
                                            amount: nil))
                    if viewerKept {
                        lines.append(LedgerLine(id: "d\(day)-payout-\(viewerID)", day: day, kind: .payout,
                                                text: "\(dayLabel)You collect \(Points.format(share, signed: true))",
                                                amount: share))
                    }
                }
                pot = 0
            }
        }

        // Standings: active members only, viewer first, then by name.
        var standings: [MemberStanding] = []
        for m in members where m.leftDay == nil {
            standings.append(standing(for: m,
                                      group: group,
                                      currentDay: currentDay,
                                      net: nets[m.userID] ?? 0,
                                      history: histories[m.userID] ?? [],
                                      keptKeys: keptKeys))
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

        let ledger: [LedgerLine] = Array(lines.reversed().prefix(ledgerCap))

        return GroupSummary(currentDay: currentDay,
                            cycle: currentDay / 30 + 1,
                            dayInCycle: currentDay % 30 + 1,
                            glyphNumber: currentDay + 1,
                            pot: pot,
                            totalForfeited: totalForfeited,
                            standings: standings,
                            ledger: ledger,
                            viewer: viewer)
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

    // MARK: - Helpers

    private static func key(_ userID: String, _ day: Int) -> String {
        return "\(day)|\(userID)"
    }

    private static func displayName(_ m: MemberInfo, viewerID: String) -> String {
        if m.userID == viewerID {
            return "You"
        }
        let trimmed: String = m.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Someone" : trimmed
    }

    private static func nameLess(_ aName: String, _ aID: String, _ bName: String, _ bID: String) -> Bool {
        let a: String = aName.lowercased()
        let b: String = bName.lowercased()
        if a != b {
            return a < b
        }
        return aID < bID
    }

    /// Deduplicated by userID (first wins), sorted by name for deterministic ledger order.
    private static func orderedMembers(_ input: [MemberInfo]) -> [MemberInfo] {
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

    private static func standing(for m: MemberInfo,
                                 group: GroupInfo,
                                 currentDay: Int,
                                 net: Double,
                                 history: [DayOutcome],
                                 keptKeys: Set<String>) -> MemberStanding {
        let checkedInToday: Bool = keptKeys.contains(key(m.userID, currentDay))

        var trailing: Int = 0
        for outcome in history.reversed() {
            if outcome != .kept {
                break
            }
            trailing += 1
        }
        let streak: Int = trailing + (checkedInToday ? 1 : 0)

        var best: Int = 0
        var run: Int = 0
        for outcome in history {
            if outcome == .kept {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }
        best = max(best, streak)

        var missedYesterday: Bool = false
        if currentDay >= 1 {
            let yesterday: Int = currentDay - 1
            if participates(m, day: yesterday, group: group) && !keptKeys.contains(key(m.userID, yesterday)) {
                missedYesterday = true
            }
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
                              missedYesterday: missedYesterday)
    }
}
