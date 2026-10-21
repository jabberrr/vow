import Foundation

enum StreakMilestones {
    static let ladder: [Int] = [3, 7, 14, 30, 50, 100, 150, 200, 250, 300, 365]

    /// Ladder values, then every 100 after 365.
    static func isMilestone(_ n: Int) -> Bool {
        if ladder.contains(n) {
            return true
        }
        return n > 365 && n % 100 == 0
    }

    /// Smallest milestone strictly greater than `streak`.
    static func next(after streak: Int) -> Int {
        for m in ladder where m > streak {
            return m
        }
        return (max(streak, 365) / 100 + 1) * 100
    }

    /// Largest milestone <= `streak`, or 0.
    static func previous(atOrBelow streak: Int) -> Int {
        if streak >= 400 {
            return (streak / 100) * 100
        }
        var best: Int = 0
        for m in ladder where m <= streak {
            best = m
        }
        return best
    }
}

enum StreakEvent: Equatable {
    case milestone(Int)
    case newBest(Int)
}

enum StreakEvents {
    /// Longest run of kept days that ended in a miss (the run still going at the end is excluded).
    /// Excused days neither break nor extend a run.
    static func previousRecord(_ history: [DayOutcome]) -> Int {
        var best: Int = 0
        var run: Int = 0
        for outcome in history {
            switch outcome {
            case .kept:
                run += 1
            case .missed:
                best = max(best, run)
                run = 0
            case .excused:
                break
            }
        }
        return best
    }

    /// What to celebrate for having just reached `streak` (today included); nil for nothing.
    /// A milestone wins over a new best.
    static func event(streak: Int, history: [DayOutcome]) -> StreakEvent? {
        guard streak > 0 else { return nil }
        if StreakMilestones.isMilestone(streak) {
            return .milestone(streak)
        }
        let record: Int = previousRecord(history)
        if record >= 3 && streak == record + 1 {
            return .newBest(streak)
        }
        return nil
    }
}
