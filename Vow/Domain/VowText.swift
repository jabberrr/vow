import Foundation

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
