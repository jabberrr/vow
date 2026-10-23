import XCTest
@testable import Vow

final class ReactionsTests: XCTestCase {

    // MARK: - Fixtures

    /// 2026-01-01T00:00:00Z = 2025-12-31 19:00 in New York.
    private let created: Date = Date(timeIntervalSince1970: 1_767_225_600)

    private func makeGroup() -> GroupInfo {
        return GroupInfo(id: GroupID(zoneName: "group-reactions", ownerName: "owner"),
                         name: "Reactions",
                         stake: 2,
                         createdAt: created,
                         timeZoneID: "America/New_York",
                         isTest: true,
                         testDay: 1,
                         epoch: 0,
                         ownerUserID: "me",
                         shareURL: nil)
    }

    private func member(_ id: String, _ name: String) -> MemberInfo {
        return MemberInfo(userID: id, displayName: name, vow: "I will read", joinedDay: 0, joinedEpoch: 0, leftDay: nil)
    }

    /// Theo's record comes first, so Settlement's order (by name) differs from the snapshot's.
    private func snapshot(_ reactions: [ReactionInfo]) -> GroupSnapshot {
        let members: [MemberInfo] = [member("theo", "Theo"), member("me", "Ari"), member("maya", "Maya")]
        var snap: GroupSnapshot = GroupSnapshot(group: makeGroup(), members: members, checkIns: [], fetchedAt: created)
        snap.reactions = reactions
        return snap
    }

    private func react(_ userID: String, _ emoji: String, on postID: String = "post-1") -> ReactionInfo {
        return ReactionInfo(userID: userID, postID: postID, emoji: emoji, serverDate: nil)
    }

    private func emojis(_ chips: [ReactionCount]?) -> [String] {
        var out: [String] = []
        for chip in chips ?? [] {
            out.append(chip.emoji)
        }
        return out
    }

    // MARK: - Counts

    func testOneReactionPerUserAndPostTheLaterWins() {
        let snap: GroupSnapshot = snapshot([react("me", "❤️"), react("maya", "❤️"), react("me", "👍")])
        let chips: [ReactionCount]? = Reactions.counts(in: snap, viewerID: "me")["post-1"]
        XCTAssertEqual(chips, [ReactionCount(emoji: "❤️", userIDs: ["maya"], mine: false),
                               ReactionCount(emoji: "👍", userIDs: ["me"], mine: true)])
    }

    func testTakingBackDropsTheReaction() {
        let snap: GroupSnapshot = snapshot([react("me", "❤️"), react("maya", "🔥", on: "post-2"), react("me", ""),
                                            react("theo", "", on: "post-3")])
        let all: [String: [ReactionCount]] = Reactions.counts(in: snap, viewerID: "me")
        XCTAssertEqual(Set(all.keys), ["post-2"])

        // Reacting again after taking it back counts again.
        let again: GroupSnapshot = snapshot([react("me", "❤️"), react("me", ""), react("me", "😮")])
        XCTAssertEqual(emojis(Reactions.counts(in: again, viewerID: "me")["post-1"]), ["😮"])
    }

    func testChipsFollowTheChoicesOrder() {
        let snap: GroupSnapshot = snapshot([react("maya", "🔥"), react("theo", "❤️"), react("me", "👍")])
        XCTAssertEqual(emojis(Reactions.counts(in: snap, viewerID: "me")["post-1"]), ["❤️", "👍", "🔥"])
        XCTAssertEqual(Reactions.choices, ["❤️", "👍", "😂", "😮", "🔥", "👏"])
    }

    func testUnknownEmojiComeAfterTheChoicesAsTheyFirstAppear() {
        // Your 🎉 is replaced by 😂, so 🎉 first appears with Maya, after Theo's 🦄.
        let snap: GroupSnapshot = snapshot([react("me", "🎉"), react("me", "😂"), react("theo", "🦄"),
                                            react("maya", "🎉")])
        let chips: [ReactionCount]? = Reactions.counts(in: snap, viewerID: "me")["post-1"]
        XCTAssertEqual(emojis(chips), ["😂", "🦄", "🎉"])
        XCTAssertEqual(chips?.last?.userIDs, ["maya"])
    }

    func testWhoReactedIsInMemberOrderWithNonMembersLast() {
        let snap: GroupSnapshot = snapshot([react("theo", "👏"), react("zoe", "👏"), react("me", "👏"),
                                            react("abe", "👏"), react("maya", "👏")])
        let chip: ReactionCount? = Reactions.counts(in: snap, viewerID: "me")["post-1"]?.first
        XCTAssertEqual(chip?.userIDs, ["me", "maya", "theo", "abe", "zoe"])
        XCTAssertEqual(chip?.count, 5)
    }

    func testMineMarksTheViewersChip() {
        let snap: GroupSnapshot = snapshot([react("me", "❤️"), react("maya", "❤️"), react("theo", "😂"),
                                            react("maya", "🔥", on: "post-2")])
        let hers: [String: [ReactionCount]] = Reactions.counts(in: snap, viewerID: "maya")
        XCTAssertEqual(hers["post-1"], [ReactionCount(emoji: "❤️", userIDs: ["me", "maya"], mine: true),
                                        ReactionCount(emoji: "😂", userIDs: ["theo"], mine: false)])
        XCTAssertEqual(hers["post-2"], [ReactionCount(emoji: "🔥", userIDs: ["maya"], mine: true)])
        XCTAssertNil(hers["post-3"])

        // Without a viewer nothing is yours.
        let nobody: [String: [ReactionCount]] = Reactions.counts(in: snap, viewerID: nil)
        XCTAssertEqual(nobody["post-1"]?.map { (chip: ReactionCount) -> Bool in chip.mine }, [false, false])
    }
}
