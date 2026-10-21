import SwiftUI

/// One day of activity: title plus its lines, most relevant first.
struct ActivityDay: Identifiable {
    let day: Int
    /// "Today", "Yesterday", "Oct 3" (real) / "Day 4" (test).
    let title: String
    /// Ranked (see LedgerFormat.rank).
    let lines: [LedgerLine]
    var id: Int { day }
}

/// View-layer formatting of the Domain ledger. Domain text is never edited (SettlementTests pin it);
/// it is parsed here: "Day 13 · Maya missed · −2 pts" -> "Maya missed" with "−2 pts" in the right column,
/// "Day 13 · Your check-in was overruled · −2 pts" -> "Your check-in was overruled" with your −2 pts.
enum LedgerFormat {
    /// Every day in the ledger, newest day first, lines ranked within each day. `currentDay` only names
    /// the days ("Today", "Yesterday").
    static func days(_ lines: [LedgerLine], group: GroupInfo, currentDay: Int) -> [ActivityDay] {
        var order: [Int] = []
        var buckets: [Int: [LedgerLine]] = [:]
        for line in lines {
            if buckets[line.day] == nil {
                order.append(line.day)
            }
            buckets[line.day, default: []].append(line)
        }
        let formatter: DateFormatter? = group.isTest ? nil : monthDayFormatter(group)
        var result: [ActivityDay] = []
        for day in order.sorted(by: >) {
            let name: String = title(day, group: group, currentDay: currentDay, formatter: formatter)
            result.append(ActivityDay(day: day, title: name, lines: ranked(buckets[day] ?? [])))
        }
        return result
    }

    /// Relevance: your day (.kept, .missed, your .excused) 0, .payout 1, .split/.carry 2, everyone else's
    /// day (.forfeit, their .excused) 3, .joined/.info 4.
    static func rank(_ line: LedgerLine) -> Int {
        switch line.kind {
        case .kept, .missed: return 0
        case .payout: return 1
        case .split, .carry: return 2
        case .forfeit: return 3
        case .excused: return stripped(line.text) == "You were excused" ? 0 : 3
        case .joined, .info: return 4
        }
    }

    /// Sort by (rank ascending, original index DESCENDING): the ledger is newest-first, so equal-rank
    /// lines come back in chronological (alphabetical) order.
    static func ranked(_ lines: [LedgerLine]) -> [LedgerLine] {
        let indexed: [(offset: Int, element: LedgerLine)] = Array(lines.enumerated())
        let sorted: [(offset: Int, element: LedgerLine)] = indexed.sorted { (a: (offset: Int, element: LedgerLine), b: (offset: Int, element: LedgerLine)) -> Bool in
            let ra: Int = rank(a.element)
            let rb: Int = rank(b.element)
            if ra != rb {
                return ra < rb
            }
            return a.offset > b.offset
        }
        return sorted.map { (pair: (offset: Int, element: LedgerLine)) -> LedgerLine in pair.element }
    }

    static func body(_ line: LedgerLine) -> String {
        switch line.kind {
        case .kept: return "You kept"
        case .payout: return "Your share"
        case .missed, .forfeit, .split, .carry: return splitLast(stripped(line.text)).head
        case .joined, .info, .excused: return stripped(line.text)
        }
    }

    /// Right-hand column text, or nil.
    static func trailing(_ line: LedgerLine) -> String? {
        switch line.kind {
        case .kept, .joined, .info, .excused:
            return nil
        case .missed, .payout:
            guard let amount: Double = line.amount else { return nil }
            return PointsText.string(amount, signed: true)
        case .forfeit, .split:
            guard let tail: String = splitLast(stripped(line.text)).tail else { return nil }
            return singular(tail)
        case .carry:
            // "pot carries 6 pts" -> "6 pts carried"
            guard let tail: String = splitLast(stripped(line.text)).tail else { return nil }
            let prefix: String = "pot carries "
            let amount: String = tail.hasPrefix(prefix) ? String(tail.dropFirst(prefix.count)) + " carried" : tail
            return singular(amount)
        }
    }

    /// Own amounts: Ink.points(amount). Everything else: Ink.text3.
    static func trailingTint(_ line: LedgerLine) -> Color {
        if isOwn(line.kind), let amount: Double = line.amount {
            return Ink.points(amount)
        }
        return Ink.text3
    }

    static func symbol(_ kind: LedgerLine.Kind) -> String {
        switch kind {
        case .kept: return "checkmark.circle.fill"
        case .missed: return "xmark.circle.fill"
        case .forfeit: return "minus.circle"
        case .payout: return "plus.circle.fill"
        case .split: return "divide.circle"
        case .carry: return "arrow.uturn.forward.circle"
        case .joined: return "person.crop.circle.badge.plus"
        case .info: return "person.crop.circle.badge.minus"
        case .excused: return "pause.circle"
        }
    }

    /// Symbol colour: your day in text/loss/gain, the pot carrying over in gain, the rest quiet. A day sat
    /// out moves neither points nor the streak, so it stays quiet too.
    static func tint(_ kind: LedgerLine.Kind) -> Color {
        switch kind {
        case .kept: return Ink.text
        case .missed: return Ink.loss
        case .payout, .carry: return Ink.gain
        case .forfeit, .split, .joined, .info, .excused: return Ink.text3
        }
    }

    /// .kept, .missed, .payout are the viewer's own lines. An .excused line may be yours too, but it has
    /// no amount to colour and reads quiet whoever it is about.
    static func isOwn(_ kind: LedgerLine.Kind) -> Bool {
        kind == .kept || kind == .missed || kind == .payout
    }

    /// VoiceOver: "Sam missed, minus 2 points", "Pot split 3 ways, plus 0.67 points each".
    static func spoken(_ line: LedgerLine) -> String {
        let text: String = body(line)
        guard let tail: String = trailing(line) else { return text }
        var words: [String] = []
        for word in tail.components(separatedBy: " ") {
            if word == "pts" {
                words.append("points")
            } else if word == "pt" {
                words.append("point")
            } else if word.hasPrefix("+") {
                words.append("plus " + String(word.dropFirst()))
            } else if word.hasPrefix("\u{2212}") {
                words.append("minus " + String(word.dropFirst()))
            } else {
                words.append(word)
            }
        }
        return text + ", " + words.joined(separator: " ")
    }

    // MARK: - Helpers

    /// "Today" / "Yesterday" / "Day 4" (test) / "Oct 3" in the group's time zone. A nil `formatter`
    /// is made on demand (only dates need one).
    private static func title(_ day: Int, group: GroupInfo, currentDay: Int, formatter: DateFormatter?) -> String {
        if day == currentDay {
            return "Today"
        }
        if day == currentDay - 1 {
            return "Yesterday"
        }
        if group.isTest {
            return "Day \(day + 1)"
        }
        guard let start: Date = DayClock.start(ofDay: day, group: group) else {
            return "Day \(day + 1)"
        }
        let dates: DateFormatter = formatter ?? monthDayFormatter(group)
        return dates.string(from: start)
    }

    private static func monthDayFormatter(_ group: GroupInfo) -> DateFormatter {
        let calendar: Calendar = DayClock.calendar(group.timeZoneID)
        let formatter: DateFormatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }

    /// `text` without its "Day N · " prefix.
    private static func stripped(_ text: String) -> String {
        guard text.hasPrefix("Day "), let range: Range<String.Index> = text.range(of: " · ") else { return text }
        return String(text[range.upperBound...])
    }

    /// Splits at the last " · ": "Sam missed · −2 pts" -> ("Sam missed", "−2 pts"). No separator: (text, nil).
    private static func splitLast(_ text: String) -> (head: String, tail: String?) {
        guard let range: Range<String.Index> = text.range(of: " · ", options: .backwards) else {
            return (head: text, tail: nil)
        }
        return (head: String(text[..<range.lowerBound]), tail: String(text[range.upperBound...]))
    }

    /// "1 pts" -> "1 pt" wherever it appears ("+1 pts each", "−1 pts").
    private static func singular(_ text: String) -> String {
        var words: [String] = text.components(separatedBy: " ")
        for i in words.indices where i > 0 && words[i] == "pts" {
            let number: String = words[i - 1].trimmingCharacters(in: CharacterSet(charactersIn: "+\u{2212}"))
            if number == "1" {
                words[i] = "pt"
            }
        }
        return words.joined(separator: " ")
    }
}
