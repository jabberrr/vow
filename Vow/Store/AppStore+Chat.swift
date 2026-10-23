import Foundation

/// Why today can't be excused.
enum ExcuseBlock: Equatable {
    /// Not an active member of the group.
    case notMember
    /// The vow has finished: there is no today to excuse.
    case finished
    case checkedIn
    case excused
}

/// Read-only chat conveniences. The sends live in AppStore.swift, beside the state they write.
extension AppStore {
    /// Before your first visit to a group's Chat, what arrived in the last two days counts as new.
    static let unseenWindow: TimeInterval = 2 * 86_400

    /// Someone else posted, sent an excuse, voted on your claim or reacted to your post since you last looked at
    /// the group's Chat. One pass over the group's records, with no Settlement and, until someone reacts, no
    /// allocation, so the tab bar can ask on every render.
    func hasUnseenChat(_ id: GroupID) -> Bool {
        guard let snapshot: GroupSnapshot = snapshots[id],
              let newest: Date = AppStore.latestChatActivity(snapshot, excluding: userID) else { return false }
        let seen: Date = chatSeenAt[id.zoneName] ?? Date().addingTimeInterval(-AppStore.unseenWindow)
        return newest > seen
    }

    /// What the chat dot answers to: the newest server date among the posts and excuses of everyone but
    /// `userID`, the votes others cast on `userID`'s own claims (someone deciding your day matters to you),
    /// and others' reactions to `userID`'s own posts (one taken back doesn't count). A bare check-in doesn't
    /// count: the orb and the strip already show it. nil when there is none (pending records have no date yet).
    static func latestChatActivity(_ snapshot: GroupSnapshot, excluding userID: String?) -> Date? {
        var newest: Date = .distantPast
        // Your own posts matter only for the reactions to them.
        let collectsOwn: Bool = !snapshot.reactions.isEmpty
        var ownPosts: Set<String> = []
        for p in snapshot.posts {
            if p.authorID != userID {
                newest = max(newest, p.serverDate ?? .distantPast)
            } else if collectsOwn {
                ownPosts.insert(p.id)
            }
        }
        for e in snapshot.excuses where e.userID != userID {
            newest = max(newest, e.serverDate ?? .distantPast)
        }
        for v in snapshot.votes where v.subjectID == userID && v.voterID != userID {
            newest = max(newest, v.serverDate ?? .distantPast)
        }
        for r in snapshot.reactions where r.userID != userID && !r.emoji.isEmpty && ownPosts.contains(r.postID) {
            newest = max(newest, r.serverDate ?? .distantPast)
        }
        return newest == .distantPast ? nil : newest
    }

    // MARK: - Excuses

    /// Today can still be excused: `sendExcuse` sends only then, the excuse sheet closes itself once it
    /// can't, and Chat's "+" card disables its row.
    func canExcuse(_ id: GroupID, now: Date) -> Bool {
        return excuseBlock(id, now: now) == nil
    }

    /// Why today can't be excused, or nil while it can: you are an active member of a vow that hasn't
    /// finished, and no check-in or excuse of yours counts for today yet. A scan of today's records, with
    /// no Settlement pass.
    func excuseBlock(_ id: GroupID, now: Date) -> ExcuseBlock? {
        guard let snapshot: GroupSnapshot = snapshots[id] else { return .notMember }
        if EndDate.isFinished(snapshot.group, now: now) {
            return .finished
        }
        guard let uid: String = userID, let me: MemberInfo = myMember(id), me.leftDay == nil else { return .notMember }
        let today: Int = DayClock.currentDay(snapshot.group, now: now)
        if AppStore.hasCheckIn(uid, day: today, in: snapshot) {
            return .checkedIn
        }
        if AppStore.hasExcuse(uid, day: today, in: snapshot) {
            return .excused
        }
        return nil
    }

    /// A valid check-in by `userID` on `day`, as Settlement counts one, without a Settlement pass.
    static func hasCheckIn(_ userID: String, day: Int, in s: GroupSnapshot) -> Bool {
        return s.checkIns.contains(where: { (c: CheckInInfo) -> Bool in
            c.userID == userID && c.day == day && Settlement.isValid(c, group: s.group)
        })
    }

    /// A valid excuse by `userID` on `day`, as Settlement counts one, without a Settlement pass.
    static func hasExcuse(_ userID: String, day: Int, in s: GroupSnapshot) -> Bool {
        return s.excuses.contains(where: { (e: ExcuseInfo) -> Bool in
            e.userID == userID && e.day == day && Settlement.isValid(e, group: s.group)
        })
    }
}
