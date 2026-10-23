import Foundation

/// Points for display and VoiceOver ("1 pt", "+1.33 pts", "plus 1 point").
enum PointsText {
    /// "+1.33 pts" -> ("+1.33", "pts"), "+1 pts" -> ("+1", "pt").
    static func parts(_ value: Double, signed: Bool = false) -> (number: String, unit: String) {
        let full: String = Points.format(value, signed: signed)
        guard full.hasSuffix(" pts") else {
            return (number: full, unit: "")
        }
        let number: String = String(full.dropLast(4))
        let magnitude: String = number.trimmingCharacters(in: CharacterSet(charactersIn: "+\u{2212}"))
        return (number: number, unit: magnitude == "1" ? "pt" : "pts")
    }

    /// Balance: signed unless it rounds to zero ("+14.5" / "−3" / "0"), so a zero never reads "+0".
    static func balanceParts(_ value: Double) -> (number: String, unit: String) {
        let isZero: Bool = (abs(value) * 100).rounded() == 0
        return PointsText.parts(value, signed: !isZero)
    }

    static func string(_ value: Double, signed: Bool = false) -> String {
        let split: (number: String, unit: String) = PointsText.parts(value, signed: signed)
        return split.unit.isEmpty ? split.number : split.number + " " + split.unit
    }

    static func spoken(_ value: Double, signed: Bool = false) -> String {
        let number: String = PointsText.parts(value, signed: signed).number
        var magnitude: String = number
        var prefix: String = ""
        if number.hasPrefix("+") {
            prefix = "plus "
            magnitude = String(number.dropFirst())
        } else if number.hasPrefix("\u{2212}") {
            prefix = "minus "
            magnitude = String(number.dropFirst())
        }
        let unit: String = magnitude == "1" ? "point" : "points"
        return prefix + magnitude + " " + unit
    }
}

enum StakeText {
    /// 1 -> "1 pt", 2 -> "2 pts".
    static func amount(_ stake: Int) -> String {
        stake == 1 ? "1 pt" : "\(stake) pts"
    }

    /// "2 pts a day".
    static func perDay(_ stake: Int) -> String {
        amount(stake) + " a day"
    }

    static func rule(_ stake: Int) -> String {
        if stake == 1 {
            return "Miss a day and your 1 pt goes to the ones who kept theirs."
        }
        return "Miss a day and your \(stake) pts go to the ones who kept theirs."
    }
}

/// "I will read 20 pages" -> "Read 20 pages". No verb found: the vow as is.
enum VowFormat {
    static func short(_ vow: String) -> String {
        let parts: (prefix: String, verb: String, suffix: String) = VowText.split(vow)
        guard !parts.verb.isEmpty else { return vow }
        let rest: String = parts.verb + parts.suffix
        guard let first: Character = rest.first else { return vow }
        return String(first).uppercased() + String(rest.dropFirst())
    }
}

enum NameFormat {
    /// "maya" -> "M"; empty -> "?".
    static func initial(_ name: String) -> String {
        let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first: Character = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    /// "Maya Lin" -> "Maya"; empty -> "Someone".
    static func first(_ name: String) -> String {
        let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let word: Substring = trimmed.split(separator: " ").first else { return "Someone" }
        return String(word)
    }

    /// First names; where two first names match, a last initial is added: ["Sam L.", "Sam P.", "Maya"].
    static func shortNames(_ names: [String]) -> [String] {
        var firsts: [String] = []
        var counts: [String: Int] = [:]
        for name in names {
            let f: String = NameFormat.first(name)
            firsts.append(f)
            counts[f.lowercased(), default: 0] += 1
        }
        var out: [String] = []
        for (index, name) in names.enumerated() {
            let f: String = firsts[index]
            if (counts[f.lowercased()] ?? 0) > 1, let initial: String = NameFormat.lastInitial(name) {
                out.append(f + " " + initial + ".")
            } else {
                out.append(f)
            }
        }
        return out
    }

    private static func lastInitial(_ name: String) -> String? {
        let words: [Substring] = name.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard words.count > 1, let last: Substring = words.last, let letter: Character = last.first else { return nil }
        return String(letter).uppercased()
    }
}

/// Milestone wording: what the number means in human time (the number itself is already on screen).
enum MilestoneText {
    static func title(_ event: StreakEvent) -> String {
        switch event {
        case .newBest:
            return "New best"
        case .milestone(let n):
            return MilestoneText.name(n)
        }
    }

    static func name(_ n: Int) -> String {
        switch n {
        case 3: return "Three in a row"
        case 7: return "One week"
        case 14: return "Two weeks"
        case 30: return "One month"
        case 365: return "One year"
        default: return "\(n) days"
        }
    }

    /// The one VoiceOver announcement at the settle beat.
    static func announcement(streak: Int, event: StreakEvent?) -> String {
        var text: String = streak == 1 ? "Checked in. 1-day streak." : "Checked in. \(streak)-day streak."
        if let e: StreakEvent = event {
            text += " " + MilestoneText.title(e) + "."
        }
        return text
    }
}

/// The group's vote rule in words: Group's row and sheet, and Chat's preamble.
enum VoteRuleText {
    /// "More than half", "Two thirds", "Everyone", "1 vote", "2 votes".
    static func title(_ rule: VoteRule) -> String {
        switch rule {
        case .majority: return "More than half"
        case .twoThirds: return "Two thirds"
        case .everyone: return "Everyone"
        case .count(let k): return k == 1 ? "1 vote" : "\(k) votes"
        }
    }

    /// "Check-ins and excuses count unless more than half of the others say they don't, by the end of the
    /// next day." "Everyone" reads "unless everyone else says they don't", "1 vote" "unless one of the
    /// others says they don't" and "2 votes" "unless 2 of the others say they don't".
    static func summary(_ rule: VoteRule) -> String {
        let who: String
        switch rule {
        case .majority: who = "more than half of the others say"
        case .twoThirds: who = "two thirds of the others say"
        case .everyone: who = "everyone else says"
        case .count(let k): who = k == 1 ? "one of the others says" : "\(k) of the others say"
        }
        return "Check-ins and excuses count unless \(who) they don't, by the end of the next day."
    }
}

/// Dates as the group lives them (its time zone), in the device's language.
enum DayText {
    /// "Oct 8"; "Oct 8, 2025" when the date is not in `now`'s year.
    static func date(_ date: Date, timeZoneID: String, now: Date, locale: Locale = Locale.current) -> String {
        let calendar: Calendar = DayClock.calendar(timeZoneID)
        let sameYear: Bool = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return formatter(sameYear ? "MMMd" : "yMMMd", calendar: calendar, locale: locale).string(from: date)
    }

    /// "October 2026".
    static func month(_ date: Date, timeZoneID: String, locale: Locale = Locale.current) -> String {
        let calendar: Calendar = DayClock.calendar(timeZoneID)
        return formatter("LLLLy", calendar: calendar, locale: locale).string(from: date)
    }

    /// "October 8" (VoiceOver, calendar cells).
    static func spoken(_ date: Date, timeZoneID: String, locale: Locale = Locale.current) -> String {
        let calendar: Calendar = DayClock.calendar(timeZoneID)
        return formatter("MMMMd", calendar: calendar, locale: locale).string(from: date)
    }

    /// "Since today" / "Since Oct 8": when the current streak began.
    static func since(_ start: Date, today: Date, timeZoneID: String, locale: Locale = Locale.current) -> String {
        let calendar: Calendar = DayClock.calendar(timeZoneID)
        if calendar.isDate(start, inSameDayAs: today) {
            return "Since today"
        }
        return "Since " + date(start, timeZoneID: timeZoneID, now: today, locale: locale)
    }

    /// The vow's final day: "Oct 30", or "Day 30" in a test group (its days are moved by hand); nil without an end.
    static func finalDay(_ group: GroupInfo, now: Date, locale: Locale = Locale.current) -> String? {
        guard let end: Int = group.endDay else { return nil }
        if group.isTest {
            return "Day \(end + 1)"
        }
        guard let day: Date = EndDate.finalDate(group) else { return nil }
        return date(day, timeZoneID: group.timeZoneID, now: now, locale: locale)
    }

    /// "1 day", "30 days".
    static func count(_ n: Int) -> String {
        return n == 1 ? "1 day" : "\(n) days"
    }

    /// "8:14 PM" in the group's time zone: the locale's short time style, so a 24-hour setting reads "20:14".
    static func time(_ date: Date, timeZoneID: String, locale: Locale = Locale.current) -> String {
        let calendar: Calendar = DayClock.calendar(timeZoneID)
        return DayFormatters.shared.formatter(.shortTime, calendar: calendar, locale: locale).string(from: date)
    }

    private static func formatter(_ template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        return DayFormatters.shared.formatter(.template(template), calendar: calendar, locale: locale)
    }
}

// MARK: - Formatters

/// DayText's formatters, each made once per format, time zone and locale and then shared: making one (and the
/// pattern behind a template) costs far more than formatting with it, and Chat formats a time for every row it
/// draws. A formatter is never changed once made, so any thread may format with it. A change to the device's
/// region settings empties the cache, since a preference can change without the locale's identifier changing.
private final class DayFormatters: @unchecked Sendable {
    static let shared: DayFormatters = DayFormatters()

    /// The locale's short time ("8:14 PM"), or a date template ("MMMd").
    enum Format: Hashable {
        case shortTime
        case template(String)
    }

    /// The calendar's identifier, so a formatter made for one calendar never formats for another. The time zone
    /// is the calendar's own, so a group zone that falls back to the device's follows the device. The hour cycle
    /// tells `Locale.current` with a 24-hour setting from a plain locale of the same identifier.
    private struct Key: Hashable {
        let format: Format
        let calendarID: Calendar.Identifier
        let timeZoneID: String
        let localeID: String
        let hourCycle: Locale.HourCycle
    }

    private let lock: NSLock = NSLock()
    /// Only under `lock`.
    private var made: [Key: DateFormatter] = [:]
    private var localeObserver: NSObjectProtocol? = nil

    private init() {
        localeObserver = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification,
                                                                object: nil,
                                                                queue: nil) { [weak self] (_: Notification) in
            self?.removeAll()
        }
    }

    func formatter(_ format: Format, calendar: Calendar, locale: Locale) -> DateFormatter {
        let key: Key = Key(format: format, calendarID: calendar.identifier, timeZoneID: calendar.timeZone.identifier,
                           localeID: locale.identifier, hourCycle: locale.hourCycle)
        lock.lock()
        defer { lock.unlock() }
        if let cached: DateFormatter = made[key] {
            return cached
        }
        let fresh: DateFormatter = DayFormatters.make(format, calendar: calendar, locale: locale)
        made[key] = fresh
        return fresh
    }

    private func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        made.removeAll()
    }

    /// Locale first: setting it can reset the formatter's calendar to the locale's own, so the group's
    /// Gregorian calendar and time zone go on after it.
    private static func make(_ format: Format, calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        switch format {
        case .shortTime:
            formatter.timeStyle = .short
        case .template(let template):
            formatter.setLocalizedDateFormatFromTemplate(template)
        }
        return formatter
    }
}
