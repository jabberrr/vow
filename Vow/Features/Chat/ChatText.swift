import Foundation

/// The Chat tab's wording: card titles, the status line and vote counts, day headers, pointers, reactions
/// and the "+" card. Pure, so every phrasing can be tested; dates follow the group's time zone in the given
/// locale.
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

    /// The card's status line under its vote buttons. The buttons carry the counts and the header's
    /// "Overruled" tag the verdict, so the line says how many it takes to overrule (until it is) and when
    /// voting ends, or "Closed" once it has. nil without voters (a solo group), where nothing can be
    /// overruled. "2 needed to overrule · Voting ends tomorrow night", "Voting ends tonight", "Closed".
    static func status(_ tally: ClaimTally, today: Int, isTest: Bool) -> String? {
        guard tally.voters > 0 else { return nil }
        guard tally.isOpen else { return "Closed" }
        let ends: String = window(day: tally.day, today: today, isTest: isTest)
        if tally.overruled {
            return ends
        }
        return "\(tally.needed) needed to overrule · " + ends
    }

    /// When voting on day `day` ends: at the end of the next day, so "tomorrow night" for today's claims and
    /// "tonight" for yesterday's. A test group's days move by hand, so it names the day whose start closes it.
    static func window(day: Int, today: Int, isTest: Bool) -> String {
        if isTest {
            return "Voting ends when Day \(day + 3) begins"
        }
        return day >= today ? "Voting ends tomorrow night" : "Voting ends tonight"
    }

    /// "Counts" or "Doesn't count": a vote, as the controls and the list of who voted say it.
    static func vote(_ counts: Bool) -> String {
        return counts ? "Counts" : "Doesn't count"
    }

    /// A vote button's VoiceOver value, for the number beside it: "No votes", "1 vote", "3 votes".
    static func voteCount(_ n: Int) -> String {
        if n == 0 {
            return "No votes"
        }
        return n == 1 ? "1 vote" : "\(n) votes"
    }

    /// Why the other choice is off once your vote can't change (`Review.canChangeVote`), for VoiceOver.
    static let voteLocked: String = "Votes can't change in the last \(Int(Review.voteChangeMargin / 60)) minutes"

    /// A line read as sentences: "2 needed to overrule. Voting ends tonight".
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

    /// A message's VoiceOver value: its time, "Sending" or "Not sent", then its reactions: "8:21 PM, 2 ❤️,
    /// 1 😂".
    static func messageValue(time: String, sending: Bool, failed: Bool, reactions: [ReactionCount]) -> String {
        var parts: [String] = [failed ? "Not sent" : (sending ? "Sending" : time)]
        for reaction in reactions {
            parts.append("\(reaction.count) \(reaction.emoji)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Reactions

    /// A message's VoiceOver action for one of `Reactions.choices`: "React with ❤️", or "Remove ❤️" for the
    /// one you have, which takes it back.
    static func reactAction(_ emoji: String, isMine: Bool) -> String {
        return isMine ? "Remove " + emoji : "React with " + emoji
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
