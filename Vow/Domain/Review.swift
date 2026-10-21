import Foundation

/// What a member claims for a day: a check-in, or an excuse with its text.
enum ClaimKind: Equatable {
    case checkIn
    case excuse(String)
}

/// One member's claim on one group day: the key of `Review.tallies`.
struct ClaimKey: Hashable {
    let subject: String
    let day: Int
}

/// Everything the UI needs about one claim: its votes, what it takes to overrule it, and whether the
/// group can still vote.
struct ClaimTally: Equatable {
    let subject: String
    let day: Int
    let kind: ClaimKind
    /// Server date of the check-in or excuse; nil while pending.
    let claimedAt: Date?
    let voters: Int
    /// "Doesn't count" votes that overrule the claim; 0 when voters == 0.
    let needed: Int
    /// Valid "Counts" votes.
    let countsVotes: Int
    /// Valid "Doesn't count" votes.
    let againstVotes: Int
    let overruled: Bool
    /// Still accepting votes.
    let isOpen: Bool
    /// userID → counts, window-valid votes only (for "your vote" and avatars).
    let votes: [String: Bool]
}

/// The group's review of check-ins and excuses. A claim stands unless enough of the other members taking
/// part that day vote "Doesn't count" by the end of the next day, so day d's points and streaks are
/// provisional until day d + 1 ends. Settlement, `tally` and `tallies` reach every verdict through `verdict`.
enum Review {
    /// An excuse stands unless the group overrules it, as a check-in does: one rule for everything you
    /// post. false would make an excuse need the group's "Counts" votes instead.
    static let excuseStandsByDefault: Bool = true
    /// The rule log keeps this many changes; the oldest go first.
    static let ruleLogCap: Int = 64
    /// A vote already cast stops changing this long before voting on its day closes. A vote is one record,
    /// judged by when it last changed, so a change the server takes after the close (a slow clock, a slow
    /// network) wouldn't fall back to the earlier choice: the vote would drop out of every tally and
    /// re-settle a closed day. A first vote has nothing to lose, so it is taken until the close.
    static let voteChangeMargin: TimeInterval = 30 * 60

    // MARK: - Window

    /// Votes on day `day` are still accepted: the group's clock is at most day + 1 (and not before `day`).
    static func isOpen(day: Int, group: GroupInfo, now: Date) -> Bool {
        return isOpen(day: day, today: DayClock.currentDay(group, now: now))
    }

    /// When voting on `day` closes (start of day + 2); nil for test groups.
    static func closesAt(day: Int, group: GroupInfo) -> Date? {
        if group.isTest {
            return nil
        }
        return DayClock.start(ofDay: day + 2, group: group)
    }

    /// A vote you have cast on a claim of day `day` may still change: voting is open and, in a real group,
    /// doesn't close within `voteChangeMargin`. At 23:30 on the day after, a change is refused while a first
    /// vote still goes in. A test group judges votes by the day they were cast, so a change counts until the
    /// owner moves the day on.
    static func canChangeVote(day: Int, group: GroupInfo, now: Date) -> Bool {
        guard isOpen(day: day, group: group, now: now) else { return false }
        guard let closes: Date = closesAt(day: day, group: group) else { return true }
        return now < closes.addingTimeInterval(-voteChangeMargin)
    }

    // MARK: - Rule

    /// The rule of the latest change from `day` or before; "More than half" without one.
    static func rule(forDay day: Int, group: GroupInfo) -> VoteRule {
        return rule(forDay: day, in: group.voteRules ?? [])
    }

    /// The log after the owner picks `rule` today. It takes effect tomorrow, so no day already open or
    /// closed is judged again under it: changes planned from tomorrow on are replaced, and nothing is
    /// added when tomorrow already has that rule.
    static func changing(_ group: GroupInfo, to picked: VoteRule, now: Date) -> [VoteRuleChange] {
        let tomorrow: Int = DayClock.currentDay(group, now: now) + 1
        var log: [VoteRuleChange] = []
        for change in group.voteRules ?? [] where change.fromDay < tomorrow {
            log.append(change)
        }
        if rule(forDay: tomorrow, in: log) != picked {
            log.append(VoteRuleChange(fromDay: tomorrow, rule: picked))
        }
        if log.count > ruleLogCap {
            log.removeFirst(log.count - ruleLogCap)
        }
        return log
    }

    // MARK: - Claims

    /// Everyone else taking part on `day` may vote on `subject`'s claim, in Settlement's member order.
    static func eligibleVoters(subject: String, day: Int, snapshot: GroupSnapshot) -> [String] {
        let members: [MemberInfo] = Settlement.orderedMembers(snapshot.members)
        return voters(of: subject, among: Settlement.participating(members, day: day, group: snapshot.group))
    }

    /// Everything the UI needs about one claim. nil when `subject` has no valid check-in or excuse on `day`,
    /// or doesn't take part that day (a claim then settles nothing).
    static func tally(subject: String, day: Int, snapshot: GroupSnapshot, now: Date) -> ClaimTally? {
        let group: GroupInfo = snapshot.group
        let key: ClaimKey = ClaimKey(subject: subject, day: day)
        guard let found: Claim = claims(in: snapshot, days: day...day)[key] else { return nil }
        let participants: [MemberInfo] = Settlement.participating(Settlement.orderedMembers(snapshot.members),
                                                                  day: day, group: group)
        return tally(key, claim: found, participants: participants,
                     ballots: Ballots(snapshot.votes, group: group, days: day...day), group: group,
                     today: DayClock.currentDay(group, now: now))
    }

    /// `tally` for every claim from day 0 through today, built in one pass: one vote index, and each
    /// day's participants worked out once (the Chat feed shows them all).
    static func tallies(snapshot: GroupSnapshot, now: Date) -> [ClaimKey: ClaimTally] {
        let group: GroupInfo = snapshot.group
        let today: Int = DayClock.currentDay(group, now: now)
        let members: [MemberInfo] = Settlement.orderedMembers(snapshot.members)
        let ballots: Ballots = Ballots(snapshot.votes, group: group, days: 0...today)
        var participantsByDay: [Int: [MemberInfo]] = [:]
        var out: [ClaimKey: ClaimTally] = [:]
        for (key, found) in claims(in: snapshot, days: 0...today) {
            let participants: [MemberInfo]
            if let known: [MemberInfo] = participantsByDay[key.day] {
                participants = known
            } else {
                participants = Settlement.participating(members, day: key.day, group: group)
                participantsByDay[key.day] = participants
            }
            out[key] = tally(key, claim: found, participants: participants, ballots: ballots, group: group,
                             today: today)
        }
        return out
    }

    /// The day proof sent now attaches to: today once you have checked in or sent an excuse, else
    /// yesterday if you had a claim then (an 11:50 pm check-in whose photo comes in the morning). Those
    /// are the only days still open to votes, so the claim can still be judged with the proof in view.
    /// nil without either, or when you don't take part that day. A finished vow's final day takes proof
    /// until the day after it ends.
    static func proofDay(for userID: String, snapshot: GroupSnapshot, now: Date) -> Int? {
        let group: GroupInfo = snapshot.group
        let today: Int = DayClock.currentDay(group, now: now)
        // The first record of a member counts, as in Settlement.
        let record: MemberInfo? = snapshot.members.first { (m: MemberInfo) -> Bool in m.userID == userID }
        guard let member: MemberInfo = record else { return nil }
        let found: [ClaimKey: Claim] = claims(in: snapshot, days: max(0, today - 1)...today)
        for day in [today, today - 1] where found[ClaimKey(subject: userID, day: day)] != nil {
            if Settlement.participates(member, day: day, group: group) {
                return day
            }
        }
        return nil
    }

    // MARK: - Verdict

    /// The count on one claim.
    struct Verdict: Equatable {
        let voters: Int
        /// 0 when voters == 0.
        let needed: Int
        let countsVotes: Int
        let againstVotes: Int
        let overruled: Bool
        /// voterID → counts.
        let votes: [String: Bool]
    }

    /// The one verdict on `subject`'s claim for `day`, for Settlement and `tally` alike. `participants`:
    /// the deduplicated members taking part that day; everyone among them but the subject may vote. With
    /// no voters (a solo group) nothing is overruled.
    static func verdict(subject: String, day: Int, isExcuse: Bool, participants: [MemberInfo], rule: VoteRule,
                        ballots: Ballots) -> Verdict {
        let eligible: [String] = voters(of: subject, among: participants)
        var votes: [String: Bool] = [:]
        var countsVotes: Int = 0
        var againstVotes: Int = 0
        for vote in ballots.votes(subject: subject, day: day) where eligible.contains(vote.voterID) {
            votes[vote.voterID] = vote.counts
            if vote.counts {
                countsVotes += 1
            } else {
                againstVotes += 1
            }
        }
        let needed: Int = eligible.isEmpty ? 0 : rule.needed(voters: eligible.count)
        let overruled: Bool
        if eligible.isEmpty {
            overruled = false
        } else if isExcuse && !excuseStandsByDefault {
            overruled = countsVotes < needed
        } else {
            overruled = againstVotes >= needed
        }
        return Verdict(voters: eligible.count, needed: needed, countsVotes: countsVotes, againstVotes: againstVotes,
                       overruled: overruled, votes: votes)
    }

    /// Every vote that counts toward a claim on one of `days`, indexed once per Settlement pass or tallying:
    /// in the group's epoch and in time. One per voter and claim, the first in the snapshot's order.
    /// Eligibility depends on the claim's day and subject, so `verdict` checks it.
    struct Ballots {
        private var byClaim: [ClaimKey: [VoteInfo]] = [:]

        init(_ votes: [VoteInfo], group: GroupInfo, days: ClosedRange<Int>) {
            for v in votes where v.epoch == group.epoch && days.contains(v.day) && Review.isInTime(v, group: group) {
                let key: ClaimKey = ClaimKey(subject: v.subjectID, day: v.day)
                if let cast: [VoteInfo] = byClaim[key],
                   cast.contains(where: { (c: VoteInfo) -> Bool in c.voterID == v.voterID }) {
                    continue
                }
                byClaim[key, default: []].append(v)
            }
        }

        func votes(subject: String, day: Int) -> [VoteInfo] {
            return byClaim[ClaimKey(subject: subject, day: day)] ?? []
        }
    }

    // MARK: - Helpers

    /// Day `day` takes votes from its own day through the next. `today - 1` can't overflow: the clock's day
    /// is never negative.
    private static func isOpen(day: Int, today: Int) -> Bool {
        return day <= today && today - 1 <= day
    }

    /// A vote is in time for its claim when pending; in a test group, when cast by the day after
    /// (`castDay` stands in for the server's clock, as test check-ins skip it); in a real group, when
    /// served by the end of the day after, plus the grace period. `v.day` is within a pass's days, so
    /// adding to it can't overflow.
    private static func isInTime(_ v: VoteInfo, group: GroupInfo) -> Bool {
        guard let served: Date = v.serverDate else {
            return true
        }
        if group.isTest {
            return v.castDay <= v.day + 1
        }
        return DayClock.lands(served, in: 0...(v.day + 1), group: group)
    }

    /// The latest change from `day` or before (a later entry wins a tie); "More than half" without one.
    private static func rule(forDay day: Int, in log: [VoteRuleChange]) -> VoteRule {
        var rule: VoteRule = .majority
        var since: Int = Int.min
        for change in log where change.fromDay <= day && change.fromDay >= since {
            rule = change.rule
            since = change.fromDay
        }
        return rule
    }

    private static func voters(of subject: String, among participants: [MemberInfo]) -> [String] {
        var out: [String] = []
        for m in participants where m.userID != subject {
            out.append(m.userID)
        }
        return out
    }

    /// A valid check-in or excuse, and when the server took it.
    private struct Claim {
        let kind: ClaimKind
        /// The earliest served copy's date; nil only while every copy is pending.
        let at: Date?
    }

    /// Every valid claim on `days`, by subject and day. A check-in wins over an excuse (only a race makes
    /// both). Of duplicate records, the earliest served one dates the claim, and gives an excuse its text.
    private static func claims(in snapshot: GroupSnapshot, days: ClosedRange<Int>) -> [ClaimKey: Claim] {
        let group: GroupInfo = snapshot.group
        var out: [ClaimKey: Claim] = [:]
        for c in snapshot.checkIns where days.contains(c.day) && Settlement.isValid(c, group: group) {
            let key: ClaimKey = ClaimKey(subject: c.userID, day: c.day)
            out[key] = Claim(kind: .checkIn, at: earlier(out[key]?.at, c.serverDate))
        }
        for e in snapshot.excuses where days.contains(e.day) && Settlement.isValid(e, group: group) {
            let key: ClaimKey = ClaimKey(subject: e.userID, day: e.day)
            if let found: Claim = out[key], found.kind == .checkIn || earlier(found.at, e.serverDate) == found.at {
                continue
            }
            out[key] = Claim(kind: .excuse(e.text), at: e.serverDate)
        }
        return out
    }

    /// `found`'s tally; nil when its subject doesn't take part on its day. `participants`: that day's.
    private static func tally(_ key: ClaimKey, claim found: Claim, participants: [MemberInfo], ballots: Ballots,
                              group: GroupInfo, today: Int) -> ClaimTally? {
        guard participants.contains(where: { (m: MemberInfo) -> Bool in m.userID == key.subject }) else { return nil }
        let result: Verdict = verdict(subject: key.subject, day: key.day, isExcuse: found.kind != .checkIn,
                                      participants: participants, rule: rule(forDay: key.day, group: group),
                                      ballots: ballots)
        return ClaimTally(subject: key.subject,
                          day: key.day,
                          kind: found.kind,
                          claimedAt: found.at,
                          voters: result.voters,
                          needed: result.needed,
                          countsVotes: result.countsVotes,
                          againstVotes: result.againstVotes,
                          overruled: result.overruled,
                          isOpen: isOpen(day: key.day, today: today),
                          votes: result.votes)
    }

    /// The earlier of two server dates, ignoring a pending (nil) one.
    private static func earlier(_ a: Date?, _ b: Date?) -> Date? {
        guard let x: Date = a else { return b }
        guard let y: Date = b else { return x }
        return min(x, y)
    }
}
