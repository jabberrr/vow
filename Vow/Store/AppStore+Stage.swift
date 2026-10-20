import Foundation

/// Read-only conveniences. Nothing here mutates state. Views call `summaries()` once per body and
/// pass the map to `Overview`, `mostUrgentGroupID(in:)` and `reminderGroups(_:)`.
extension AppStore {
    /// One Settlement pass per group.
    func summaries(now: Date = Date()) -> [GroupID: GroupSummary] {
        var out: [GroupID: GroupSummary] = [:]
        let viewerID: String = userID ?? ""
        for id in groupIDs {
            if let snapshot: GroupSnapshot = snapshots[id] {
                out[id] = Settlement.summarize(snapshot, viewerID: viewerID, now: now)
            }
        }
        return out
    }

    var testGroupIDs: Set<GroupID> {
        var out: Set<GroupID> = []
        for (id, snapshot) in snapshots where snapshot.group.isTest {
            out.insert(id)
        }
        return out
    }

    /// The open vow with the least time left (real groups before test groups; ties keep store order).
    func mostUrgentGroupID(in all: [GroupID: GroupSummary], now: Date = Date(), excluding: GroupID? = nil) -> GroupID? {
        var best: GroupID? = nil
        var bestLeft: Double = 0
        for id in groupIDs {
            if let skip: GroupID = excluding, skip == id {
                continue
            }
            guard let summary: GroupSummary = all[id], Digest.isOpen(summary),
                  let group: GroupInfo = snapshots[id]?.group else { continue }
            let left: Double = DayWindow.secondsLeft(group, now: now) ?? 1_000_000_000
            if best == nil || left < bestLeft {
                best = id
                bestLeft = left
            }
        }
        return best
    }

    /// Real, unfinished groups where you are an active member with a vow, in store order.
    func reminderGroups(_ all: [GroupID: GroupSummary]) -> [ReminderGroup] {
        var out: [ReminderGroup] = []
        for id in groupIDs {
            guard let snapshot: GroupSnapshot = snapshots[id], !snapshot.group.isTest,
                  let summary: GroupSummary = all[id], !summary.isFinished,
                  let viewer: MemberStanding = summary.viewer, !viewer.vow.isEmpty else { continue }
            out.append(ReminderGroup(id: id, name: snapshot.group.name, keptToday: viewer.checkedInToday, streak: viewer.streak))
        }
        return out
    }
}
