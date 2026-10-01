import Foundation

enum GroupFormat {
    /// 1 -> "1 pt", 2 -> "2 pts".
    static func stake(_ points: Int) -> String {
        points == 1 ? "1 pt" : "\(points) pts"
    }

    static func members(_ count: Int) -> String {
        count == 1 ? "1 member" : "\(count) members"
    }

    /// When `member` joined (in the current epoch): "Oct 1" for real groups, "Day 3" for test groups.
    static func since(member: MemberInfo?, group: GroupInfo) -> String {
        guard let member = member else { return "—" }
        let day: Int = member.joinedEpoch == group.epoch ? member.joinedDay : 0
        if group.isTest {
            return "Day \(day + 1)"
        }
        let calendar: Calendar = DayClock.calendar(group.timeZoneID)
        let start: Date = calendar.startOfDay(for: group.createdAt)
        let date: Date = calendar.date(byAdding: .day, value: day, to: start) ?? start
        let formatter: DateFormatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
