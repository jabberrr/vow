import Foundation

/// One emoji's reactions on one post: the chip under a message.
struct ReactionCount: Equatable, Hashable {
    let emoji: String
    /// Who reacted with it, in Settlement's member order (non-members last, by userID).
    let userIDs: [String]
    /// The viewer is among them.
    let mine: Bool

    var count: Int { userIDs.count }
}

/// Reactions to chat posts, read from the snapshot's records. A reaction record is overwritten, never
/// deleted, so the last copy of each (user, post) is the one that counts and "" means taken back.
enum Reactions {
    /// What a long press on a message offers, in order.
    static let choices: [String] = ["❤️", "👍", "😂", "😮", "🔥", "👏"]

    /// Every post's chips, by postID: one reaction per (user, post) (a later array element wins a
    /// duplicate), "" dropped, `choices` first in their order and then any other emoji as it first appears.
    /// Posts without a reaction are absent. One call covers the whole chat, for the feed's memo.
    static func counts(in snapshot: GroupSnapshot, viewerID: String?) -> [String: [ReactionCount]] {
        var last: [Key: Int] = [:]
        for (index, reaction) in snapshot.reactions.enumerated() {
            last[Key(reaction)] = index
        }

        // Each post's emoji in order of first appearance, and who reacted with each.
        var emojis: [String: [String]] = [:]
        var reacted: [String: [String: [String]]] = [:]
        for (index, reaction) in snapshot.reactions.enumerated() where !reaction.emoji.isEmpty && last[Key(reaction)] == index {
            if reacted[reaction.postID]?[reaction.emoji] == nil {
                emojis[reaction.postID, default: []].append(reaction.emoji)
            }
            reacted[reaction.postID, default: [:]][reaction.emoji, default: []].append(reaction.userID)
        }

        let rank: [String: Int] = memberRank(snapshot.members)
        var out: [String: [ReactionCount]] = [:]
        for (postID, found) in emojis {
            var chips: [ReactionCount] = []
            for emoji in ordered(found) {
                let userIDs: [String] = inMemberOrder(reacted[postID]?[emoji] ?? [], rank: rank)
                let mine: Bool = viewerID.map { (id: String) -> Bool in userIDs.contains(id) } ?? false
                chips.append(ReactionCount(emoji: emoji, userIDs: userIDs, mine: mine))
            }
            out[postID] = chips
        }
        return out
    }

    // MARK: - Helpers

    /// `choices` first, in their order, then any other emoji (a later build's) as it first appeared.
    private static func ordered(_ found: [String]) -> [String] {
        var out: [String] = []
        for choice in choices where found.contains(choice) {
            out.append(choice)
        }
        for emoji in found where !choices.contains(emoji) {
            out.append(emoji)
        }
        return out
    }

    /// Each member's place in Settlement's order.
    private static func memberRank(_ members: [MemberInfo]) -> [String: Int] {
        var rank: [String: Int] = [:]
        for (index, m) in Settlement.orderedMembers(members).enumerated() {
            rank[m.userID] = index
        }
        return rank
    }

    /// Members in Settlement's order (those who have left included), then anyone without a member record
    /// by userID.
    private static func inMemberOrder(_ userIDs: [String], rank: [String: Int]) -> [String] {
        return userIDs.sorted { (a: String, b: String) -> Bool in
            let aRank: Int = rank[a] ?? Int.max
            let bRank: Int = rank[b] ?? Int.max
            if aRank != bRank {
                return aRank < bRank
            }
            return a < b
        }
    }

    /// One reaction per (user, post).
    private struct Key: Hashable {
        let userID: String
        let postID: String

        init(_ reaction: ReactionInfo) {
            userID = reaction.userID
            postID = reaction.postID
        }
    }
}
