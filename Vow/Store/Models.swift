import Foundation

// MARK: - Stake

enum Stake: String, Codable, CaseIterable, Identifiable {
    case one, two, five, points

    var id: String { rawValue }

    var label: String {
        switch self {
        case .one: return "$1"
        case .two: return "$2"
        case .five: return "$5"
        case .points: return "Points"
        }
    }

    var amount: Double {
        switch self {
        case .one: return 1
        case .two: return 2
        case .five: return 5
        case .points: return 10
        }
    }

    var isPoints: Bool { self == .points }

    /// Dollars: "$2", "$1.50", "+$0.67", "−$2". Points: "10 pts", "+3.3 pts".
    /// Negative values always use the Unicode minus "−".
    func format(_ value: Double, signed: Bool = false) -> String {
        let mag: Double = abs(value)
        let body: String
        let isZero: Bool
        if isPoints {
            let rounded: Double = (mag * 10).rounded() / 10
            isZero = rounded == 0
            if abs(rounded - rounded.rounded()) < 0.0001 {
                body = String(format: "%.0f pts", rounded)
            } else {
                body = String(format: "%.1f pts", rounded)
            }
        } else {
            let rounded: Double = (mag * 100).rounded() / 100
            isZero = rounded == 0
            if abs(rounded - rounded.rounded()) < 0.0001 {
                body = String(format: "$%.0f", rounded)
            } else {
                body = String(format: "$%.2f", rounded)
            }
        }
        let sign: String
        if value < 0 && !isZero {
            sign = "\u{2212}"
        } else if signed {
            sign = "+"
        } else {
            sign = ""
        }
        return sign + body
    }
}

// MARK: - Crew

struct Mate: Codable, Hashable, Identifiable {
    let name: String
    let reliability: Double
    var id: String { name }
}

enum Crew: String, Codable, CaseIterable, Identifiable {
    case nightShift, pageCount, solo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nightShift: return "Night Shift"
        case .pageCount: return "The Page Count"
        case .solo: return "Solo"
        }
    }

    var mates: [Mate] {
        switch self {
        case .nightShift:
            return [Mate(name: "Mara", reliability: 0.95),
                    Mate(name: "Devon", reliability: 0.7),
                    Mate(name: "Priya", reliability: 0.85)]
        case .pageCount:
            return [Mate(name: "Theo", reliability: 0.9),
                    Mate(name: "Lena", reliability: 0.6)]
        case .solo:
            return []
        }
    }

    var subtitle: String {
        switch self {
        case .nightShift: return "Mara, Devon, Priya"
        case .pageCount: return "Theo, Lena"
        case .solo: return "Just you"
        }
    }
}

enum DayMark: String, Codable {
    case kept, missed
}

enum MemberStatus: String {
    case checkedIn, missed, notYet, yourMove

    var label: String {
        switch self {
        case .checkedIn: return "checked in"
        case .missed: return "missed"
        case .notYet: return "not yet"
        case .yourMove: return "your move"
        }
    }
}

struct CrewMemberRow: Identifiable {
    let id: String
    let name: String
    let isYou: Bool
    let status: MemberStatus
}

// MARK: - Ledger & state

struct LedgerEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case sealed, kept, missed, forfeit, payout, carry, cycle, info
    }

    var id: UUID = UUID()
    var cycle: Int
    var day: Int
    var kind: Kind
    var text: String
    var amount: Double? = nil
    var date: Date = Date()
}

struct VowState: Codable, Equatable {
    var vow: String
    var crew: Crew
    var stake: Stake
    var swornAt: Date
    var cycle: Int
    var day: Int
    var sealedToday: Bool
    var streak: Int
    var bestStreak: Int
    var history: [DayMark]
    var todayRolls: [String: Bool]
    var lastResults: [String: Bool]
    var pot: Double
    var cyclePot: Double
    var net: Double
    var ledger: [LedgerEntry]
}

extension VowState {
    /// Streak including today once sealed (advanceDay is what actually bumps `streak`).
    var liveStreak: Int { streak + (sealedToday ? 1 : 0) }
}

// MARK: - Vow text

enum VowText {
    private static let skipPhrases: [[String]] = [
        ["i'm", "going", "to"],
        ["im", "going", "to"],
        ["i", "am", "going", "to"],
        ["i", "will"],
        ["i'll"],
        ["i"],
        ["will"],
        ["to"]
    ]

    /// "I will train for 30 minutes" -> ("I will ", "train", " for 30 minutes").
    /// If no verb remains after skipping, returns (whole, "", "").
    static func split(_ vow: String) -> (prefix: String, verb: String, suffix: String) {
        let s: String = vow
        var words: [Range<String.Index>] = []
        var i: String.Index = s.startIndex
        while i < s.endIndex {
            if s[i].isWhitespace {
                i = s.index(after: i)
                continue
            }
            let start: String.Index = i
            while i < s.endIndex && !s[i].isWhitespace {
                i = s.index(after: i)
            }
            words.append(start..<i)
        }

        var normalized: [String] = []
        for r in words {
            normalized.append(String(s[r]).lowercased().replacingOccurrences(of: "\u{2019}", with: "'"))
        }

        var w: Int = 0
        var matched: Bool = true
        while matched && w < words.count {
            matched = false
            for phrase in skipPhrases {
                if w + phrase.count <= words.count && Array(normalized[w..<(w + phrase.count)]) == phrase {
                    w += phrase.count
                    matched = true
                    break
                }
            }
        }

        if w >= words.count {
            return (prefix: s, verb: "", suffix: "")
        }

        let r: Range<String.Index> = words[w]
        var end: String.Index = r.upperBound
        while end > r.lowerBound {
            let prev: String.Index = s.index(before: end)
            if prev > r.lowerBound && s[prev].isPunctuation {
                end = prev
            } else {
                break
            }
        }
        let prefix = String(s[s.startIndex..<r.lowerBound])
        let verb = String(s[r.lowerBound..<end])
        let suffix = String(s[end..<s.endIndex])
        return (prefix: prefix, verb: verb, suffix: suffix)
    }
}
