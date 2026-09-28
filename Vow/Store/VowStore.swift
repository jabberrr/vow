import Foundation
import Observation

@Observable final class VowStore {
    static let cycleLength: Int = 30
    static let ledgerCap: Int = 200

    private(set) var state: VowState? = nil
    var toast: String? = nil

    private let persistence: Persistence
    @ObservationIgnored private var themeCache: DailyTheme? = nil

    init(defaults: UserDefaults = .standard) {
        let p = Persistence(defaults: defaults)
        self.persistence = p
        self.state = p.load()
    }

    // MARK: - Derived

    var theme: DailyTheme {
        let c: Int = state?.cycle ?? 1
        let d: Int = state?.day ?? 1
        if let cached = themeCache, cached.cycle == c, cached.day == d {
            return cached
        }
        let fresh = DailyTheme.make(cycle: c, day: d)
        themeCache = fresh
        return fresh
    }

    var crewRows: [CrewMemberRow] {
        guard let s = state else { return [] }
        var rows: [CrewMemberRow] = [
            CrewMemberRow(id: "you", name: "You", isYou: true,
                          status: s.sealedToday ? .checkedIn : .yourMove)
        ]
        for mate in s.crew.mates {
            let status: MemberStatus
            if s.todayRolls[mate.name] == true {
                status = .checkedIn
            } else if s.lastResults[mate.name] == false {
                status = .missed
            } else {
                status = .notYet
            }
            rows.append(CrewMemberRow(id: mate.name, name: mate.name, isYou: false, status: status))
        }
        return rows
    }

    /// Deterministic mate rolls for a given day.
    static func rolls(crew: Crew, cycle: Int, day: Int) -> [String: Bool] {
        var rng = Mulberry32(seed: FNV1a.hash("vow|\(cycle)|\(day)|crew"))
        var out: [String: Bool] = [:]
        for mate in crew.mates {
            out[mate.name] = rng.next() < mate.reliability
        }
        return out
    }

    // MARK: - Mutations

    func start(vow: String, crew: Crew, stake: Stake) {
        let text: String = vow.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = VowState(
            vow: text,
            crew: crew,
            stake: stake,
            swornAt: Date(),
            cycle: 1,
            day: 1,
            sealedToday: false,
            streak: 0,
            bestStreak: 0,
            history: [],
            todayRolls: VowStore.rolls(crew: crew, cycle: 1, day: 1),
            lastResults: [:],
            pot: 0,
            cyclePot: 0,
            net: 0,
            ledger: []
        )
        let perDay: String = stake.format(stake.amount) + "/day"
        VowStore.appendLedger(&s, LedgerEntry(cycle: 1, day: 1, kind: .info,
                                     text: "Vow sworn \u{00B7} \(crew.title) \u{00B7} \(perDay)"))
        commit(s)
        toast = "Vow sworn. Day 1."
    }

    func seal() {
        guard var s = state, !s.sealedToday else { return }
        s.sealedToday = true
        VowStore.appendLedger(&s, LedgerEntry(cycle: s.cycle, day: s.day, kind: .sealed, text: "You checked in"))
        commit(s)
        toast = "Sealed. Streak \(s.liveStreak)."
    }

    func advanceDay() {
        guard var s = state else { return }
        let stake: Stake = s.stake
        let amt: Double = stake.amount
        let cycle: Int = s.cycle
        let day: Int = s.day
        let youKept: Bool = s.sealedToday

        // Your mark + streak.
        s.history.append(youKept ? .kept : .missed)
        s.streak = youKept ? s.streak + 1 : 0
        s.bestStreak = max(s.bestStreak, s.streak)
        VowStore.appendLedger(&s, LedgerEntry(cycle: cycle, day: day, kind: youKept ? .kept : .missed,
                                     text: "Day \(day) \u{00B7} you \(youKept ? "kept" : "missed")"))

        // Forfeits.
        var forfeits: Double = 0
        var keepers: Int = youKept ? 1 : 0
        var yourDelta: Double = 0
        if !youKept {
            forfeits += amt
            s.net -= amt
            yourDelta -= amt
            VowStore.appendLedger(&s, LedgerEntry(cycle: cycle, day: day, kind: .forfeit,
                                         text: "You missed \u{00B7} forfeit \(stake.format(amt))",
                                         amount: -amt))
        }
        for mate in s.crew.mates {
            if s.todayRolls[mate.name] == true {
                keepers += 1
            } else {
                forfeits += amt
                VowStore.appendLedger(&s, LedgerEntry(cycle: cycle, day: day, kind: .forfeit,
                                             text: "\(mate.name) missed \u{00B7} forfeits \(stake.format(amt))"))
            }
        }
        s.pot += forfeits
        s.cyclePot += forfeits

        // Split or carry.
        if keepers > 0 {
            if s.pot > 0 {
                let share: Double = s.pot / Double(keepers)
                let ways: String = keepers == 1 ? "1 way" : "\(keepers) ways"
                VowStore.appendLedger(&s, LedgerEntry(cycle: cycle, day: day, kind: .info,
                                             text: "Pot split \(ways) \u{00B7} \(stake.format(share)) each"))
                if youKept {
                    s.net += share
                    yourDelta += share
                    VowStore.appendLedger(&s, LedgerEntry(cycle: cycle, day: day, kind: .payout,
                                                 text: "You collect \(stake.format(share, signed: true))",
                                                 amount: share))
                }
                s.pot = 0
            } else {
                VowStore.appendLedger(&s, LedgerEntry(cycle: cycle, day: day, kind: .info,
                                             text: "Clean sweep \u{00B7} everyone kept"))
            }
        } else {
            VowStore.appendLedger(&s, LedgerEntry(cycle: cycle, day: day, kind: .carry,
                                         text: "Nobody kept \u{00B7} pot carries \(stake.format(s.pot))"))
        }

        s.lastResults = s.todayRolls

        // Next day / cycle rollover.
        s.day += 1
        var newCycle: Bool = false
        if s.day > VowStore.cycleLength {
            s.cycle += 1
            s.day = 1
            s.cyclePot = 0
            s.net = 0
            newCycle = true
            VowStore.appendLedger(&s, LedgerEntry(cycle: s.cycle, day: 1, kind: .cycle,
                                         text: "Cycle \(String(format: "%02d", s.cycle)) begins"))
        }
        s.sealedToday = false
        s.todayRolls = VowStore.rolls(crew: s.crew, cycle: s.cycle, day: s.day)
        commit(s)

        var msg: String = "Day \(day) \u{00B7} \(youKept ? "kept" : "missed")"
        if abs(yourDelta) >= 0.005 {
            msg += " \u{00B7} " + stake.format(yourDelta, signed: true)
        }
        if newCycle {
            msg += " \u{00B7} Cycle \(String(format: "%02d", s.cycle))"
        }
        toast = msg
    }

    func reset() {
        state = nil
        toast = nil
        themeCache = nil
        persistence.clear()
    }

    // MARK: - Helpers

    private func commit(_ s: VowState) {
        state = s
        persistence.save(s)
    }

    /// Inserts newest-first and caps the ledger.
    private static func appendLedger(_ s: inout VowState, _ entry: LedgerEntry) {
        s.ledger.insert(entry, at: 0)
        if s.ledger.count > ledgerCap {
            s.ledger.removeLast(s.ledger.count - ledgerCap)
        }
    }
}
