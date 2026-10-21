import Foundation

/// The Chat tab's wording: card titles, the status line, day headers, pointers and the "+" card. Pure, so
/// every phrasing can be tested; dates follow the group's time zone in the given locale.
enum ChatText {
    /// A claim's time while it saves: "Run 5k before work · Sending…".
    static let sending: String = "Sending…"

    // MARK: - Cards

    /// "Maya checked in", "You sent an excuse".
    static func title(name: String, isMine: Bool, kind: ClaimKind) -> String {
        let who: String = isMine ? "You" : name
        switch kind {
        case .checkIn:
            return who + " checked in"
        case .excuse:
            return who + " sent an excuse"
        }
    }

    /// VoiceOver's reading of a card's header: "Maya checked in, 8:14 PM, Swim 40 lengths, overruled".
    /// `time` is the claim's time, or "Sending".
    static func spokenHeader(title: String, time: String, vow: String, overruled: Bool) -> String {
        var parts: [String] = [title, time]
        if !vow.isEmpty {
            parts.append(vow)
        }
        if overruled {
            parts.append("overruled")
        }
        return parts.joined(separator: ", ")
    }

    /// The card's status line, with one denominator ("needed"): the votes so far and when voting ends, or
    /// "Closed" and the votes once it has. nil without voters (a solo group), where nothing can be overruled.
    /// "2 say it counts · Voting ends tomorrow night", "Closed · 3 said it doesn't count", "Closed".
    static func status(_ tally: ClaimTally, today: Int, isTest: Bool) -> String? {
        guard tally.voters > 0 else { return nil }
        let said: String? = votes(tally)
        if tally.isOpen {
            let ends: String = window(day: tally.day, today: today, isTest: isTest)
            guard let count: String = said else { return ends }
            return count + " · " + ends
        }
        guard let count: String = said else { return "Closed" }
        return "Closed · " + count
    }

    /// When voting on day `day` ends: at the end of the next day, so "tomorrow night" for today's claims and
    /// "tonight" for yesterday's. A test group's days move by hand, so it names the day whose start closes it.
    static func window(day: Int, today: Int, isTest: Bool) -> String {
        if isTest {
            return "Voting ends when Day \(day + 3) begins"
        }
        return day >= today ? "Voting ends tomorrow night" : "Voting ends tonight"
    }

    /// "1 of 3 needed to overrule" until enough say it doesn't count, then "3 said it doesn't count". With no
    /// "Doesn't count" votes, "2 say it counts" ("said" once voting has closed). nil without votes.
    static func votes(_ tally: ClaimTally) -> String? {
        let against: Int = tally.againstVotes
        if tally.needed > 0 && against >= tally.needed {
            return "\(against) said it doesn't count"
        }
        if against > 0 {
            return "\(against) of \(tally.needed) needed to overrule"
        }
        let n: Int = tally.countsVotes
        guard n > 0 else { return nil }
        if tally.isOpen {
            return n == 1 ? "1 says it counts" : "\(n) say it counts"
        }
        return n == 1 ? "1 said it counts" : "\(n) said it counts"
    }

    /// "Counts" or "Doesn't count": a vote, as the controls and the list of who voted say it.
    static func vote(_ counts: Bool) -> String {
        return counts ? "Counts" : "Doesn't count"
    }

    /// Why the other choice is off once your vote can't change (`Review.canChangeVote`), for VoiceOver.
    static let voteLocked: String = "Votes can't change in the last \(Int(Review.voteChangeMargin / 60)) minutes"

    /// A line read as sentences: "2 say it counts. Voting ends tonight".
    static func spoken(_ line: String) -> String {
        return line.replacingOccurrences(of: " · ", with: ". ")
    }

    // MARK: - Feed

    /// A day's section header: "Today", "Yesterday", "Oct 19"; "Day 4" in a test group.
    static func header(day: Int, today: Int, group: GroupInfo, now: Date, locale: Locale = Locale.current) -> String {
        if group.isTest {
            return "Day \(day + 1)"
        }
        if day == today {
            return "Today"
        }
        if day == today - 1 {
            return "Yesterday"
        }
        return date(day, group: group, now: now, locale: locale)
    }

    /// "Maya added proof to yesterday's check-in", "You added proof to Oct 19's excuse", "… to Day 4's
    /// check-in" in a test group. The day is the claim's, relative to today.
    static func pointer(name: String, isMine: Bool, claimDay: Int, isExcuse: Bool, today: Int, group: GroupInfo,
                        now: Date, locale: Locale = Locale.current) -> String {
        let who: String = isMine ? "You" : name
        let whose: String = possessive(claimDay, today: today, group: group, now: now, locale: locale)
        return who + " added proof to " + whose + (isExcuse ? " excuse" : " check-in")
    }

    /// What Chat is for, before anything has happened. Solo, nothing can be overruled, so it doesn't say so.
    static func emptyBody(hasVoters: Bool) -> String {
        let shows: String = "Check-ins, proof and excuses show up here."
        guard hasVoters else { return shows }
        return shows + " Each one counts unless the group overrules it by the end of the next day."
    }

    /// A message's VoiceOver value: its time, "Sending" or "Not sent".
    static func messageValue(time: String, sending: Bool, failed: Bool) -> String {
        if failed {
            return "Not sent"
        }
        return sending ? "Sending" : time
    }

    // MARK: - "+" card

    /// The proof rows' header: the claim proof sent now attaches to, or why there is none ("Add proof after
    /// you check in"; "This vow has ended" once a finished vow's last day has closed).
    static func plusHeader(proofDay: Int?, kind: ClaimKind?, today: Int, isFinished: Bool) -> String {
        guard let day: Int = proofDay else {
            return isFinished ? "This vow has ended" : "Add proof after you check in"
        }
        var claim: String = "check-in"
        if case .excuse(_)? = kind {
            claim = "excuse"
        }
        return "Proof for " + (day >= today ? "today's " : "yesterday's ") + claim
    }

    /// Why "Excuse for today" is off (`AppStore.excuseBlock`); nil while today can still be excused.
    static func excuseNote(_ block: ExcuseBlock?) -> String? {
        switch block {
        case .none:
            return nil
        case .some(.notMember):
            return "Write your vow to join"
        case .some(.finished):
            return "This vow has ended"
        case .some(.checkedIn):
            return "You've checked in today"
        case .some(.excused):
            return "You're excused today"
        }
    }

    // MARK: - Helpers

    /// "today's", "yesterday's", "Oct 19's"; "Day 4's" in a test group.
    private static func possessive(_ day: Int, today: Int, group: GroupInfo, now: Date, locale: Locale) -> String {
        if group.isTest {
            return "Day \(day + 1)'s"
        }
        if day == today {
            return "today's"
        }
        if day == today - 1 {
            return "yesterday's"
        }
        return date(day, group: group, now: now, locale: locale) + "'s"
    }

    /// Group day `day` as a date: "Oct 19".
    private static func date(_ day: Int, group: GroupInfo, now: Date, locale: Locale) -> String {
        guard let start: Date = DayClock.start(ofDay: day, group: group) else { return "Day \(day + 1)" }
        return DayText.date(start, timeZoneID: group.timeZoneID, now: now, locale: locale)
    }
}
