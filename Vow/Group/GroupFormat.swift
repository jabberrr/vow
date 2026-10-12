import Foundation

enum GroupFormat {
    /// 1 -> "1 pt", 2 -> "2 pts".
    static func stake(_ points: Int) -> String {
        points == 1 ? "1 pt" : "\(points) pts"
    }
}

/// Short vow for crew rows: "I will read 20 pages" -> "Read 20 pages". No verb found: the vow as is.
enum VowFormat {
    static func short(_ vow: String) -> String {
        let parts: (prefix: String, verb: String, suffix: String) = VowText.split(vow)
        guard !parts.verb.isEmpty else { return vow }
        let rest: String = parts.verb + parts.suffix
        guard let first: Character = rest.first else { return vow }
        return String(first).uppercased() + String(rest.dropFirst())
    }
}
