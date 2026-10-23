import Foundation

/// The Chat feed of one group, worked out from its records, `Review.tallies` and `Reactions.counts`: text
/// messages with their reactions, one card per check-in or excuse with that day's proof inside it, and a
/// one-line pointer where proof arrived after the conversation had moved on, so no photo is drawn twice.
/// Pure, so the page can build it once per snapshot and minute, and the rules can be tested.
///
/// Rows run oldest first by (day, time, id), and a header starts each day. Anything still sending, or
/// failed, is dated now and kept at the end of its day in the order it was sent. Until Earlier is tapped,
/// only the week up to the newest item shows: the last seven days, or the last week anything happened in
/// a chat gone quiet or a vow that has finished, so the feed never opens on nothing but Earlier.
struct ChatFeed: Equatable {
    /// The newest item's day and the six days before it.
    static let recentDays: Int = 7
    /// A message joins its author's run when it follows the previous one within this long, the same day.
    static let runSeconds: TimeInterval = 300

    let rows: [ChatRow]
    /// Something in the epoch is older than the days shown: the feed opens with Earlier.
    let hasEarlier: Bool
    /// Two or more members take part today in a vow that hasn't finished, so a claim can be overruled: the
    /// rule's preamble shows.
    let hasVoters: Bool
    /// The day proof sent now attaches to (`Review.proofDay`), and your claim's kind on it.
    let proofDay: Int?
    let proofKind: ClaimKind?
    /// Cards opening up or gaining proof, and reactions coming and going, which the page animates.
    let shape: ChatShape

    /// Nothing at all in the epoch yet: the days shown always reach the newest item.
    var isEmpty: Bool {
        rows.isEmpty
    }

    /// A check-in with no proof (sending and failed included) and no vote (yours while it saves included)
    /// is a two-line card; anything else opens it up. An excuse always has its text to show.
    static func isCompact(_ tally: ClaimTally, proofCount: Int) -> Bool {
        return tally.kind == .checkIn && proofCount == 0 && tally.countsVotes + tally.againstVotes == 0
    }

    /// The message `postID` among the rows shown: what the reaction picker is open over.
    func message(_ postID: String) -> ChatMessage? {
        for row in rows where row.id == postID {
            if case .message(let message) = row.content {
                return message
            }
        }
        return nil
    }

    /// The scroll target of the claim card for (subject, day).
    static func cardID(_ key: ClaimKey) -> String {
        return "claim-\(key.day)-\(key.subject)"
    }

    /// The feed as `viewerID` sees it at `now`. `showAll`: Earlier was tapped, so every day of the epoch shows.
    /// Votes and reactions are counted once each, in one `Review.tallies` and one `Reactions.counts` pass;
    /// only the claims in the days shown become cards.
    static func build(_ snapshot: GroupSnapshot, viewerID: String, now: Date, showAll: Bool) -> ChatFeed {
        let group: GroupInfo = snapshot.group
        let today: Int = DayClock.currentDay(group, now: now)
        let tallies: [ClaimKey: ClaimTally] = Review.tallies(snapshot: snapshot, now: now)
        let reactions: [String: [ReactionCount]] = Reactions.counts(in: snapshot, viewerID: viewerID)
        let people: FeedPeople = FeedPeople(snapshot.members, viewerID: viewerID, group: group, now: now)

        var all: [FeedEntry] = []
        var proofs: [ClaimKey: [FeedEntry]] = [:]
        for (index, post) in snapshot.posts.enumerated() where post.epoch == group.epoch {
            let entry: FeedEntry = FeedEntry(stamp: stamp(post, index: index, group: group, now: now), item: .message(post))
            if post.isProof {
                proofs[ClaimKey(subject: post.authorID, day: post.day), default: []].append(entry)
            } else {
                all.append(entry)
            }
        }
        for (key, tally) in tallies {
            let place: FeedStamp = FeedStamp(day: key.day, pending: tally.claimedAt == nil,
                                             time: tally.claimedAt ?? now, seq: 0, id: cardID(key))
            all.append(FeedEntry(stamp: place, item: .claim(key)))
        }
        let firstDay: Int = showAll ? 0 : firstRecentDay(all, today: today)
        var entries: [FeedEntry] = []
        for entry in all where entry.stamp.day >= firstDay {
            entries.append(entry)
        }
        let hasEarlier: Bool = entries.count < all.count
        for key in Array(proofs.keys) {
            proofs[key]?.sort { (a: FeedEntry, b: FeedEntry) -> Bool in a.stamp < b.stamp }
        }
        entries.sort { (a: FeedEntry, b: FeedEntry) -> Bool in a.stamp < b.stamp }
        if !group.isTest {
            entries = withPointers(entries, proofs: proofs)
        }

        var rows: [ChatRow] = []
        var compactCards: Int = 0
        var proofCount: Int = 0
        var chipCount: Int = 0
        var section: Int? = nil
        for (index, entry) in entries.enumerated() {
            var gap: ChatGap = .item
            if entry.stamp.day != section {
                section = entry.stamp.day
                rows.append(ChatRow(id: "day-\(entry.stamp.day)", gap: .section, content: .day(entry.stamp.day)))
                gap = .none
            }
            switch entry.item {
            case .message(let post):
                let startsRun: Bool = !continuesRun(entries, at: index)
                let endsRun: Bool = index + 1 == entries.count || !continuesRun(entries, at: index + 1)
                let chips: [ReactionCount] = reactions[post.id] ?? []
                chipCount += chips.count
                let message: ChatMessage = ChatMessage(post: post,
                                                       isMine: post.authorID == viewerID,
                                                       author: people.name(post.authorID),
                                                       initial: people.initial(post.authorID),
                                                       time: entry.stamp.time,
                                                       startsRun: startsRun,
                                                       endsRun: endsRun,
                                                       reactions: chips)
                rows.append(ChatRow(id: post.id, gap: startsRun ? gap : .run, content: .message(message)))
            case .claim(let key):
                guard let tally: ClaimTally = tallies[key] else { continue }
                let claim: ChatClaim = people.claim(tally, proofs: posts(proofs[key] ?? []))
                if claim.isCompact {
                    compactCards += 1
                }
                proofCount += claim.proofs.count
                rows.append(ChatRow(id: cardID(key), gap: gap, content: .claim(claim)))
            case .pointer(let post, let key):
                guard let tally: ClaimTally = tallies[key] else { continue }
                let pointer: ChatPointer = ChatPointer(cardID: cardID(key),
                                                       author: people.name(post.authorID),
                                                       isMine: post.authorID == viewerID,
                                                       claimDay: key.day,
                                                       isExcuse: tally.kind != .checkIn,
                                                       isPending: post.serverDate == nil)
                rows.append(ChatRow(id: "pointer-" + post.id, gap: gap, content: .pointer(pointer)))
            }
        }

        let proofDay: Int? = Review.proofDay(for: viewerID, snapshot: snapshot, now: now)
        var proofKind: ClaimKind? = nil
        if let day: Int = proofDay {
            proofKind = tallies[ClaimKey(subject: viewerID, day: day)]?.kind
        }
        // After the final day nobody takes part in a day to come, so there is no rule to explain.
        let hasVoters: Bool = !EndDate.isFinished(group, now: now)
            && Settlement.participating(people.ordered, day: today, group: group).count >= 2
        return ChatFeed(rows: rows,
                        hasEarlier: hasEarlier,
                        hasVoters: hasVoters,
                        proofDay: proofDay,
                        proofKind: proofKind,
                        shape: ChatShape(compactCards: compactCards, proofs: proofCount, reactionChips: chipCount))
    }

    // MARK: - Helpers

    /// The first day shown before Earlier is tapped: six days before the newest item's day (today at the
    /// latest), so a quiet chat opens on the last week anything happened.
    private static func firstRecentDay(_ entries: [FeedEntry], today: Int) -> Int {
        var newest: Int = 0
        for entry in entries {
            newest = max(newest, entry.stamp.day)
        }
        return max(0, min(today, newest) - (recentDays - 1))
    }

    /// A post's place. A real group's message belongs to the day the server took it (today while it is
    /// sending); a test group's days move by hand, so it keeps the day it was sent on.
    private static func stamp(_ post: PostInfo, index: Int, group: GroupInfo, now: Date) -> FeedStamp {
        let pending: Bool = post.serverDate == nil
        let time: Date = post.serverDate ?? now
        let day: Int
        if group.isTest {
            day = post.day
        } else {
            day = DayClock.dayIndex(of: time, start: group.createdAt, timeZoneID: group.timeZoneID)
        }
        return FeedStamp(day: day, pending: pending, time: time, seq: pending ? index : 0, id: post.id)
    }

    /// Adds a pointer for each proof that arrived once the conversation had moved on: a message or another
    /// card lies strictly between its card and the proof. `sorted` holds messages and cards only.
    private static func withPointers(_ sorted: [FeedEntry], proofs: [ClaimKey: [FeedEntry]]) -> [FeedEntry] {
        var out: [FeedEntry] = sorted
        for (index, entry) in sorted.enumerated() where index + 1 < sorted.count {
            guard case .claim(let key) = entry.item else { continue }
            let next: FeedStamp = sorted[index + 1].stamp
            for proof in proofs[key] ?? [] where next < proof.stamp {
                guard case .message(let post) = proof.item else { continue }
                out.append(FeedEntry(stamp: proof.stamp, item: .pointer(post, key)))
            }
        }
        out.sort { (a: FeedEntry, b: FeedEntry) -> Bool in a.stamp < b.stamp }
        return out
    }

    /// `entries[index]` is a message that follows its author's previous message in the same day within
    /// `runSeconds`, with nothing in between.
    private static func continuesRun(_ entries: [FeedEntry], at index: Int) -> Bool {
        guard index > 0,
              case .message(let post) = entries[index].item,
              case .message(let previous) = entries[index - 1].item else { return false }
        let a: FeedStamp = entries[index - 1].stamp
        let b: FeedStamp = entries[index].stamp
        return previous.authorID == post.authorID && a.day == b.day && abs(b.time.timeIntervalSince(a.time)) <= runSeconds
    }

    private static func posts(_ entries: [FeedEntry]) -> [PostInfo] {
        var out: [PostInfo] = []
        for entry in entries {
            if case .message(let post) = entry.item {
                out.append(post)
            }
        }
        return out
    }
}

/// One row of the feed, with the space above it.
struct ChatRow: Equatable, Identifiable {
    enum Content: Equatable {
        /// The header of a day's section.
        case day(Int)
        case message(ChatMessage)
        case claim(ChatClaim)
        case pointer(ChatPointer)
    }

    let id: String
    let gap: ChatGap
    let content: Content

    /// Yours and not yet sent: the feed follows it to the bottom even when you had scrolled up.
    var isOwnPending: Bool {
        switch content {
        case .day:
            return false
        case .message(let message):
            return message.isMine && message.post.serverDate == nil
        case .claim(let claim):
            return claim.isMine && claim.tally.claimedAt == nil
        case .pointer(let pointer):
            return pointer.isMine && pointer.isPending
        }
    }
}

/// The space above a row: none under a day's header, a sliver between the bubbles of one run, the usual
/// space between items, and more above a header.
enum ChatGap: Equatable {
    case none, run, item, section
}

/// Counts the page animates on: a card opening up, proof arriving in one, or a reaction chip coming or going.
struct ChatShape: Equatable {
    let compactCards: Int
    let proofs: Int
    let reactionChips: Int
}

/// A text message, and its place in its author's run.
struct ChatMessage: Equatable {
    let post: PostInfo
    let isMine: Bool
    /// The author's name ("Someone" when empty).
    let author: String
    let initial: String
    /// When the server took it, or now while it is sending or failed.
    let time: Date
    /// First of its run: the name line (others) or the time (yours) goes above it.
    let startsRun: Bool
    /// Last of its run: it has the bubble's tail, and others' letter disc sits beside it.
    let endsRun: Bool
    /// Its chips, one per emoji, from the feed's one `Reactions.counts` pass.
    let reactions: [ReactionCount]

    /// Your reaction to it, if any.
    var myReaction: String? {
        reactions.first { (reaction: ReactionCount) -> Bool in reaction.mine }?.emoji
    }
}

/// A check-in or an excuse, with everything its card draws.
struct ChatClaim: Equatable {
    let tally: ClaimTally
    let isMine: Bool
    /// The subject's name ("Someone" when empty).
    let name: String
    let initial: String
    /// The subject's vow, shortened: "Swim 40 lengths".
    let vow: String
    /// The proof posted for this claim, oldest first, sending and failed proof included.
    let proofs: [PostInfo]
    /// You take part that day, it isn't yours, and voting is open.
    let canVote: Bool
    /// You may vote, and change a vote you have cast (`Review.canChangeVote`). False in voting's last half
    /// hour, when only a first vote is taken.
    let canChangeVote: Bool
    /// Your vote while it counts.
    let myVote: Bool?
    /// Who voted what: you first, then in the group's member order.
    let voters: [ChatVoter]

    var isCompact: Bool {
        ChatFeed.isCompact(tally, proofCount: proofs.count)
    }
}

/// One vote under a card's status line.
struct ChatVoter: Equatable, Identifiable {
    let id: String
    /// "You" for you.
    let name: String
    let initial: String
    let isYou: Bool
    let counts: Bool
}

/// "Maya added proof to yesterday's check-in": proof that arrived after other things were said, pointing back
/// to its card, which holds the photo.
struct ChatPointer: Equatable {
    let cardID: String
    let author: String
    let isMine: Bool
    let claimDay: Int
    let isExcuse: Bool
    let isPending: Bool
}

// MARK: - Building blocks

/// Where an item sorts: by day; within a day, what the server has taken before what is still sending; then
/// by time, then (sending only) by the order it was sent, then by id.
private struct FeedStamp: Comparable {
    let day: Int
    let pending: Bool
    let time: Date
    let seq: Int
    let id: String

    static func < (a: FeedStamp, b: FeedStamp) -> Bool {
        if a.day != b.day {
            return a.day < b.day
        }
        if a.pending != b.pending {
            return !a.pending
        }
        if a.time != b.time {
            return a.time < b.time
        }
        if a.seq != b.seq {
            return a.seq < b.seq
        }
        return a.id < b.id
    }
}

private enum FeedItem {
    case message(PostInfo)
    case claim(ClaimKey)
    case pointer(PostInfo, ClaimKey)
}

private struct FeedEntry {
    let stamp: FeedStamp
    let item: FeedItem
}

/// Names, member order and your right to vote, looked up once per build. The first record of a member
/// counts, as in Settlement.
private struct FeedPeople {
    let viewerID: String
    let group: GroupInfo
    /// The feed's clock, for whether a vote may still change.
    let now: Date
    /// Settlement's order: deduplicated, by name.
    let ordered: [MemberInfo]
    private let byID: [String: MemberInfo]
    private let rank: [String: Int]

    init(_ members: [MemberInfo], viewerID: String, group: GroupInfo, now: Date) {
        var byID: [String: MemberInfo] = [:]
        for m in members where byID[m.userID] == nil {
            byID[m.userID] = m
        }
        let ordered: [MemberInfo] = Settlement.orderedMembers(members)
        var rank: [String: Int] = [:]
        for (index, m) in ordered.enumerated() {
            rank[m.userID] = index
        }
        self.viewerID = viewerID
        self.group = group
        self.now = now
        self.ordered = ordered
        self.byID = byID
        self.rank = rank
    }

    func name(_ userID: String) -> String {
        return MemberText.name(byID[userID]?.displayName ?? "")
    }

    func initial(_ userID: String) -> String {
        return NameFormat.initial(byID[userID]?.displayName ?? "")
    }

    func claim(_ tally: ClaimTally, proofs: [PostInfo]) -> ChatClaim {
        let key: ClaimKey = ClaimKey(subject: tally.subject, day: tally.day)
        let canVote: Bool = tally.isOpen && isVoter(on: key)
        return ChatClaim(tally: tally,
                         isMine: tally.subject == viewerID,
                         name: name(tally.subject),
                         initial: initial(tally.subject),
                         vow: VowFormat.short(byID[tally.subject]?.vow ?? ""),
                         proofs: proofs,
                         canVote: canVote,
                         canChangeVote: canVote && Review.canChangeVote(day: tally.day, group: group, now: now),
                         myVote: tally.votes[viewerID],
                         voters: voters(tally.votes))
    }

    /// What `Review.eligibleVoters` says of you: someone else's claim on a day you take part in.
    private func isVoter(on key: ClaimKey) -> Bool {
        guard key.subject != viewerID, let me: MemberInfo = byID[viewerID] else { return false }
        return Settlement.participates(me, day: key.day, group: group)
    }

    private func voters(_ votes: [String: Bool]) -> [ChatVoter] {
        var out: [ChatVoter] = []
        for (voterID, counts) in votes {
            let isYou: Bool = voterID == viewerID
            out.append(ChatVoter(id: voterID, name: isYou ? "You" : name(voterID), initial: initial(voterID),
                                 isYou: isYou, counts: counts))
        }
        out.sort { (a: ChatVoter, b: ChatVoter) -> Bool in
            if a.isYou != b.isYou {
                return a.isYou
            }
            let ra: Int = rank[a.id] ?? Int.max
            let rb: Int = rank[b.id] ?? Int.max
            if ra != rb {
                return ra < rb
            }
            return a.id < b.id
        }
        return out
    }
}
