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
/// it is parsed here: "Day 13 · Maya missed · −2 pts" -> "Maya missed" with "−2 pts" in the right column.
enum LedgerFormat {
    /// The most recent SETTLED day (day < currentDay), ranked, capped at `limit`. nil if no day has settled.
    /// Today's joins never appear here (they are in ActivityView).
    static func preview(_ lines: [LedgerLine], group: GroupInfo, currentDay: Int, limit: Int = 5) -> ActivityDay? {
        var latest: Int = -1
        for line in lines where line.day < currentDay && line.day > latest {
            latest = line.day
        }
        guard latest >= 0 else { return nil }
        let dayLines: [LedgerLine] = lines.filter { $0.day == latest }
        let top: [LedgerLine] = Array(ranked(dayLines).prefix(limit))
        return ActivityDay(day: latest, title: dayTitle(latest, group: group, currentDay: currentDay), lines: top)
    }

    /// Every day in the ledger, newest day first, lines ranked within each day.
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

    /// Relevance: .kept/.missed 0, .payout 1, .split/.carry 2, .forfeit 3, .joined/.info 4.
    static func rank(_ kind: LedgerLine.Kind) -> Int {
        switch kind {
        case .kept, .missed: return 0
        case .payout: return 1
        case .split, .carry: return 2
        case .forfeit: return 3
        case .joined, .info: return 4
        }
    }

    /// Sort by (rank ascending, original index DESCENDING): the ledger is newest-first, so equal-rank
    /// lines come back in chronological (alphabetical) order.
    static func ranked(_ lines: [LedgerLine]) -> [LedgerLine] {
        let indexed: [(offset: Int, element: LedgerLine)] = Array(lines.enumerated())
        let sorted: [(offset: Int, element: LedgerLine)] = indexed.sorted { (a: (offset: Int, element: LedgerLine), b: (offset: Int, element: LedgerLine)) -> Bool in
            let ra: Int = rank(a.element.kind)
            let rb: Int = rank(b.element.kind)
            if ra != rb {
                return ra < rb
            }
            return a.offset > b.offset
        }
        return sorted.map { (pair: (offset: Int, element: LedgerLine)) -> LedgerLine in pair.element }
    }

    static func dayTitle(_ day: Int, group: GroupInfo, currentDay: Int) -> String {
        title(day, group: group, currentDay: currentDay, formatter: nil)
    }

    static func body(_ line: LedgerLine) -> String {
        switch line.kind {
        case .kept: return "You kept"
        case .missed: return "You missed"
        case .payout: return "Your share"
        case .forfeit, .split, .carry: return splitLast(stripped(line.text)).head
        case .joined, .info: return stripped(line.text)
        }
    }

    /// Right-hand column text, or nil.
    static func trailing(_ line: LedgerLine) -> String? {
        switch line.kind {
        case .kept, .joined, .info:
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

    /// Own amounts: Palette.points(amount). Everything else: Palette.text3.
    static func trailingTint(_ line: LedgerLine) -> Color {
        if isOwn(line.kind), let amount: Double = line.amount {
            return Palette.points(amount)
        }
        return Palette.text3
    }

    static func symbol(_ kind: LedgerLine.Kind) -> String {
        switch kind {
        case .kept: return "checkmark.circle.fill"
        case .missed: return "xmark.circle.fill"
        case .forfeit: return "minus.circle"
        case .payout: return "plus.circle.fill"
        case .split: return "divide.circle"
        case .carry: return "arrow.uturn.right.circle"
        case .joined: return "person.crop.circle.badge.plus"
        case .info: return "person.crop.circle.badge.minus"
        }
    }

    static func tint(_ kind: LedgerLine.Kind) -> Color {
        switch kind {
        case .kept, .payout: return Palette.kept
        case .missed: return Palette.loss
        case .carry: return Palette.warn
        case .forfeit, .split, .joined, .info: return Palette.text3
        }
    }

    /// .kept, .missed, .payout are the viewer's own lines.
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

/// A day title row and its lines, no card (the caller supplies it).
struct ActivityRows: View {
    let day: ActivityDay

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.title)
                .font(Typeface.footnoteSemibold)
                .foregroundStyle(Palette.text3)
                .padding(.top, 14)
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(day.lines) { line in
                ActivityRow(line: line)
            }
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Kind icon, text, and the amount in the right column. One VoiceOver element.
struct ActivityRow: View {
    let line: LedgerLine

    private var own: Bool {
        LedgerFormat.isOwn(line.kind)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: LedgerFormat.symbol(line.kind))
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(LedgerFormat.tint(line.kind))
                .frame(width: 17)
            Text(LedgerFormat.body(line))
                .font(Typeface.subheadline)
                .foregroundStyle(own ? Palette.text : Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LedgerFormat.spoken(line))
    }

    @ViewBuilder
    private var trailing: some View {
        if let text: String = LedgerFormat.trailing(line) {
            Text(text)
                .font(Typeface.subheadline)
                .fontWeight(own ? Font.Weight.semibold : Font.Weight.regular)
                .monospacedDigit()
                .foregroundStyle(LedgerFormat.trailingTint(line))
                .lineLimit(1)
                .layoutPriority(1)
        }
    }
}

/// Pushed from the Points card: every ledger line, grouped by day, newest first. Reads the store live.
struct ActivityView: View {
    let id: GroupID

    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content
                .padding(.horizontal, Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, Space.huge)
        }
        .screenBackground()
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
    }

    @ViewBuilder
    private var content: some View {
        if let summary = store.summary(for: id), let group = store.snapshots[id]?.group {
            dayList(LedgerFormat.days(summary.ledger, group: group, currentDay: summary.currentDay))
        }
    }

    private func dayList(_ days: [ActivityDay]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(days) { day in
                daySection(day)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func daySection(_ day: ActivityDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(day.title)
            VStack(spacing: 0) {
                ForEach(day.lines) { line in
                    if line.id != day.lines.first?.id {
                        InsetDivider(leading: 45)
                    }
                    ActivityRow(line: line)
                }
            }
            .padding(.vertical, 6)
            .card()
        }
    }
}
