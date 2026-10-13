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
