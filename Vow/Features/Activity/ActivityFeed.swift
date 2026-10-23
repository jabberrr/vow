import Foundation

/// The Activity page's days, worked out from the ledger (`GroupSummary.days`): one section per day, newest
/// first, each a few plain lines. Pure, so the page builds it once per render and the wording can be tested.
///
/// A day opens with who kept and who was excused ("You and Sam kept · Alex was excused"), then where the
/// points went: the pot carried in from earlier days, then each stake lost (yours first), each with one arrow
/// line per keeper and their part, or, when nobody kept, one arrow on to the next day. Joins and leaves close
/// the day. A day where everyone kept is a single note.
enum ActivityFeed {
    /// `titleDay` reads "Today" (see `ActivityPage.titleDay`); `votingDay` is the closed day the group can
    /// still vote on, whose header says so.
    static func build(_ days: [LedgerDay],
                      group: GroupInfo,
                      viewerID: String,
                      titleDay: Int,
                      votingDay: Int?,
                      now: Date,
                      locale: Locale = Locale.current) -> [ActivitySection] {
        let titles: DayTitles = DayTitles(group: group, today: titleDay, now: now, locale: locale)
        var sections: [ActivitySection] = []
        for day in days {
            let items: [ActivityItem] = ActivityFeed.items(day, group: group, viewerID: viewerID, titles: titles)
            if items.isEmpty {
                continue
            }
            sections.append(ActivitySection(day: day.day,
                                            title: titles.title(day.day),
                                            votesOpen: day.day == votingDay,
                                            items: items))
        }
        return sections
    }

    // MARK: - Lines

    private static func items(_ day: LedgerDay, group: GroupInfo, viewerID: String, titles: DayTitles) -> [ActivityItem] {
        var items: [ActivityItem] = []
        if let outcome: String = ActivityFeed.outcome(day, viewerID: viewerID) {
            items.append(.note(ActivityNote(id: "outcome", text: outcome)))
        }
        let keepers: [LedgerPerson] = ActivityFeed.viewerFirst(day.kept, viewerID: viewerID)
        // A pot nobody kept passes through untouched: it shows on the day it is paid out.
        if day.carriedIn > 0 && !keepers.isEmpty {
            let text: String = "Carried over from earlier days"
            let source: ActivityLine = ActivityLine(id: "carried-in", text: text, amount: day.carriedIn,
                                                    isGain: false, isViewer: false,
                                                    spoken: text + ", " + PointsText.spoken(day.carriedIn))
            let arrows: [ActivityLine] = ActivityFeed.shares(day.carriedIn, keepers: keepers, viewerID: viewerID)
            items.append(.flow(ActivityFlow(source: source, arrows: arrows)))
        }
        var forfeits: [Forfeit] = []
        for forfeit in day.forfeits where forfeit.person.userID == viewerID {
            forfeits.append(forfeit)
        }
        for forfeit in day.forfeits where forfeit.person.userID != viewerID {
            forfeits.append(forfeit)
        }
        for forfeit in forfeits {
            let text: String = ActivityFeed.forfeitText(forfeit, viewerID: viewerID)
            let source: ActivityLine = ActivityLine(id: "forfeit-" + forfeit.person.userID, text: text,
                                                    amount: -forfeit.amount, isGain: false,
                                                    isViewer: forfeit.person.userID == viewerID,
                                                    spoken: text + ", " + PointsText.spoken(-forfeit.amount))
            let arrows: [ActivityLine]
            if keepers.isEmpty {
                arrows = [ActivityFeed.carry(forfeit.amount, day: day.day, group: group, titles: titles)]
            } else {
                arrows = ActivityFeed.shares(forfeit.amount, keepers: keepers, viewerID: viewerID)
            }
            items.append(.flow(ActivityFlow(source: source, arrows: arrows)))
        }
        if let membership: String = ActivityFeed.membership(day, viewerID: viewerID) {
            items.append(.note(ActivityNote(id: "membership", text: membership)))
        }
        return items
    }

    /// An equal part of `amount` to each keeper: "You +1 pt", "Sam +1 pt".
    private static func shares(_ amount: Double, keepers: [LedgerPerson], viewerID: String) -> [ActivityLine] {
        let part: Double = amount / Double(keepers.count)
        var arrows: [ActivityLine] = []
        for keeper in keepers {
            let isViewer: Bool = keeper.userID == viewerID
            let name: String = ActivityFeed.name(keeper, viewerID: viewerID)
            arrows.append(ActivityLine(id: keeper.userID, text: name, amount: part, isGain: true, isViewer: isViewer,
                                       spoken: PointsText.spoken(part) + " to " + (isViewer ? "you" : name)))
        }
        return arrows
    }

    /// A stake nobody kept, on to the next day: "Carried to today", "Carried to Tue, Oct 20", "Carried to
    /// Day 5". After a vow's final day there is no next day, so it stays: "Left in the pot".
    private static func carry(_ amount: Double, day: Int, group: GroupInfo, titles: DayTitles) -> ActivityLine {
        let place: String
        if let end: Int = group.endDay, day >= end {
            place = "left in the pot"
        } else {
            place = "carried to " + titles.destination(day + 1)
        }
        let text: String = place.prefix(1).uppercased() + place.dropFirst()
        return ActivityLine(id: "carry", text: text, amount: amount, isGain: false, isViewer: false,
                            spoken: PointsText.spoken(amount) + " " + place)
    }

    // MARK: - Words

    /// "You and Sam kept · Alex was excused", "Everyone kept", "Nobody kept", "Everyone was excused"; nil for a
    /// day that hasn't closed, or that nobody took part in.
    static func outcome(_ day: LedgerDay, viewerID: String) -> String? {
        guard day.isClosed else { return nil }
        var parts: [String] = []
        if !day.kept.isEmpty {
            let everyone: Bool = day.kept.count > 1 && day.excused.isEmpty && day.forfeits.isEmpty
            parts.append(everyone ? "Everyone kept" : ActivityFeed.names(day.kept, viewerID: viewerID) + " kept")
        } else if !day.forfeits.isEmpty {
            parts.append("Nobody kept")
        }
        if !day.excused.isEmpty {
            if day.excused.count > 1 && day.kept.isEmpty && day.forfeits.isEmpty {
                parts.append("Everyone was excused")
            } else {
                let one: Bool = day.excused.count == 1 && day.excused[0].userID != viewerID
                parts.append(ActivityFeed.names(day.excused, viewerID: viewerID) + (one ? " was excused" : " were excused"))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Alex joined", "You and Maya joined · Sam left"; nil when nobody did.
    static func membership(_ day: LedgerDay, viewerID: String) -> String? {
        var parts: [String] = []
        if !day.joined.isEmpty {
            parts.append(ActivityFeed.names(day.joined, viewerID: viewerID) + " joined")
        }
        if !day.left.isEmpty {
            parts.append(ActivityFeed.names(day.left, viewerID: viewerID) + " left")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Maya missed", "Your check-in was overruled", "Maya's excuse was overruled".
    static func forfeitText(_ forfeit: Forfeit, viewerID: String) -> String {
        let name: String = ActivityFeed.name(forfeit.person, viewerID: viewerID)
        let whose: String = forfeit.person.userID == viewerID ? "Your" : name + "'s"
        switch forfeit.reason {
        case .missed:
            return name + " missed"
        case .checkInOverruled:
            return whose + " check-in was overruled"
        case .excuseOverruled:
            return whose + " excuse was overruled"
        }
    }

    /// "You", "You and Sam", "You, Maya and Sam": you first, everyone else in Settlement's order.
    static func names(_ people: [LedgerPerson], viewerID: String) -> String {
        var words: [String] = []
        for person in ActivityFeed.viewerFirst(people, viewerID: viewerID) {
            words.append(ActivityFeed.name(person, viewerID: viewerID))
        }
        guard let last: String = words.last else { return "" }
        if words.count == 1 {
            return last
        }
        return words.dropLast().joined(separator: ", ") + " and " + last
    }

    /// "You" for the viewer; a blank name reads "Someone".
    static func name(_ person: LedgerPerson, viewerID: String) -> String {
        if person.userID == viewerID {
            return "You"
        }
        let trimmed: String = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Someone" : trimmed
    }

    /// `people` with you moved to the front; everyone else keeps Settlement's order.
    private static func viewerFirst(_ people: [LedgerPerson], viewerID: String) -> [LedgerPerson] {
        var mine: [LedgerPerson] = []
        var others: [LedgerPerson] = []
        for person in people {
            if person.userID == viewerID {
                mine.append(person)
            } else {
                others.append(person)
            }
        }
        return mine + others
    }
}

// MARK: - Model

/// One day of the Activity page.
struct ActivitySection: Identifiable, Equatable {
    let day: Int
    /// "Today", "Yesterday", "Tue, Oct 20"; "Day 4" in a test group.
    let title: String
    /// The group can still vote on this day, so its points can still change.
    let votesOpen: Bool
    let items: [ActivityItem]

    var id: Int { day }

    /// The day's one note when it is all there is and nothing is left to vote on: it then sits on the header's
    /// line ("Tue, Oct 20 … Everyone kept").
    var quietNote: ActivityNote? {
        guard !votesOpen, items.count == 1, case .note(let note) = items[0] else { return nil }
        return note
    }

    /// VoiceOver's header: "Yesterday, votes still open".
    var spokenTitle: String {
        votesOpen ? title + ", votes still open" : title
    }
}

/// A line of a day: words alone, or points on the move.
enum ActivityItem: Identifiable, Equatable {
    case note(ActivityNote)
    case flow(ActivityFlow)

    var id: String {
        switch self {
        case .note(let note):
            return note.id
        case .flow(let flow):
            return flow.id
        }
    }
}

/// Who kept or was excused, or who joined or left: "You and Sam kept · Alex was excused".
struct ActivityNote: Identifiable, Equatable {
    let id: String
    let text: String

    /// The parts read as sentences: "You and Sam kept. Alex was excused".
    var spoken: String {
        text.replacingOccurrences(of: " · ", with: ". ")
    }
}

/// Points on the move: a stake lost (or the pot carried in), then one arrow line for each place it went.
struct ActivityFlow: Identifiable, Equatable {
    let source: ActivityLine
    let arrows: [ActivityLine]

    var id: String { source.id }

    /// One VoiceOver element: "Maya missed, minus 2 points. 1 point to you, 1 point to Sam".
    var spoken: String {
        var parts: [String] = []
        for arrow in arrows {
            parts.append(arrow.spoken)
        }
        return source.spoken + ". " + parts.joined(separator: ", ")
    }
}

/// Words on the left and points on the right: "Maya missed −2 pts"; on an arrow, "You +1 pt" or
/// "Carried to today 2 pts".
struct ActivityLine: Identifiable, Equatable {
    let id: String
    let text: String
    /// As it reads: −2 for a stake lost, +1 for a keeper's part; the pot's amounts are positive.
    let amount: Double
    /// Points someone gained: "+1 pt". A stake lost carries its own "−", and the pot reads plain ("2 pts").
    let isGain: Bool
    /// Yours: the one amount in colour.
    let isViewer: Bool
    /// VoiceOver: "Maya missed, minus 2 points", "1 point to you", "2 points carried to today".
    let spoken: String

    var amountText: String {
        PointsText.string(amount, signed: isGain)
    }
}

/// Names group days as the page's headers do: "Today", "Yesterday", "Tue, Oct 20" ("Tue, Dec 30, 2025" in
/// another year), "Day 4" in a test group. Its two formatters are made once per build.
private struct DayTitles {
    let group: GroupInfo
    /// The day that reads "Today".
    let today: Int
    let calendar: Calendar
    let year: Int
    let thisYear: DateFormatter
    let otherYear: DateFormatter

    init(group: GroupInfo, today: Int, now: Date, locale: Locale) {
        let calendar: Calendar = DayClock.calendar(group.timeZoneID)
        self.group = group
        self.today = today
        self.calendar = calendar
        self.year = calendar.component(.year, from: now)
        self.thisYear = DayTitles.formatter("MMMEd", calendar: calendar, locale: locale)
        self.otherYear = DayTitles.formatter("yMMMEd", calendar: calendar, locale: locale)
    }

    func title(_ day: Int) -> String {
        if day == today {
            return "Today"
        }
        if day == today - 1 {
            return "Yesterday"
        }
        if group.isTest {
            return "Day \(day + 1)"
        }
        guard let start: Date = DayClock.start(ofDay: day, group: group) else { return "Day \(day + 1)" }
        let sameYear: Bool = calendar.component(.year, from: start) == year
        return (sameYear ? thisYear : otherYear).string(from: start)
    }

    /// A day mid-sentence: "today", "yesterday", "Tue, Oct 20", "Day 5".
    func destination(_ day: Int) -> String {
        if day == today {
            return "today"
        }
        if day == today - 1 {
            return "yesterday"
        }
        return title(day)
    }

    /// Locale first: setting it can reset the formatter's calendar to the locale's own.
    private static func formatter(_ template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
