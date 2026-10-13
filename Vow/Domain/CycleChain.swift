import Foundation

enum ChainBead: Equatable {
    case kept(day: Int)
    case missed(day: Int)
    case today(day: Int, kept: Bool)
    case upcoming
    case notJoined
}

enum CycleChain {
    static let length: Int = 30

    /// The member's current 30-day cycle. `history` is MemberStanding.history (closed days since
    /// joining, oldest first), so the first participating day is currentDay - history.count.
    static func beads(history: [DayOutcome], currentDay: Int, checkedInToday: Bool) -> [ChainBead] {
        let today: Int = max(0, currentDay)
        let start: Int = (today / length) * length
        let joined: Int = max(0, today - history.count)
        var out: [ChainBead] = []
        out.reserveCapacity(length)
        for i in 0..<length {
            let day: Int = start + i
            if day > today {
                out.append(.upcoming)
            } else if day == today {
                out.append(.today(day: day, kept: checkedInToday))
            } else if day < joined {
                out.append(.notJoined)
            } else {
                let index: Int = day - joined
                if index >= 0 && index < history.count && history[index] == .kept {
                    out.append(.kept(day: day))
                } else {
                    out.append(.missed(day: day))
                }
            }
        }
        return out
    }

    /// VoiceOver: "This cycle: 15 kept, 2 missed, today open".
    static func summaryText(_ beads: [ChainBead]) -> String {
        var kept: Int = 0
        var missed: Int = 0
        var todayText: String = ""
        for bead in beads {
            switch bead {
            case .kept:
                kept += 1
            case .missed:
                missed += 1
            case .today(_, let isKept):
                todayText = isKept ? "today kept" : "today open"
            case .upcoming, .notJoined:
                break
            }
        }
        var parts: [String] = ["\(kept) kept", "\(missed) missed"]
        if !todayText.isEmpty {
            parts.append(todayText)
        }
        return "This cycle: " + parts.joined(separator: ", ")
    }
}
