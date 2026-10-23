import SwiftUI

/// What a claim card asks of the page.
struct ClaimCardActions {
    /// Your vote: true "Counts", false "Doesn't count".
    let vote: (Bool) -> Void
    /// A tap on proof: the viewer, by post id.
    let openMedia: (String) -> Void
    /// A failed proof of yours: send it again, or delete it.
    let retry: (String) -> Void
    let discard: (String) -> Void
}

/// One member's check-in or excuse for a day: the day's proof inside it, the group's votes, and when voting
/// ends. A check-in nobody has voted on or shown proof for is compact (two lines and two round vote buttons);
/// anything else opens it up. The sphere carries the verdict: lit (it counts), dashed (excused) or unlit with
/// "Overruled". A vote's colour is its choice, green for "Counts" and red for "Doesn't count", never points.
struct ClaimCard: View {
    let claim: ChatClaim
    let groupID: GroupID
    let timeZoneID: String
    /// The group's clock day, for when voting ends.
    let today: Int
    let isTest: Bool
    /// You may vote: one of its voters, a member, and voting is open.
    let canVote: Bool
    let failedPosts: Set<String>
    /// The page's height, which caps the proof's height.
    let pageHeight: CGFloat
    let actions: ClaimCardActions

    @Environment(\.dynamicTypeSize) private var typeSize: DynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    /// The list of who voted what is open.
    @State private var showsVoters: Bool = false

    private static let sphereSize: CGFloat = 32

    init(claim: ChatClaim,
         groupID: GroupID,
         timeZoneID: String,
         today: Int,
         isTest: Bool,
         canVote: Bool,
         failedPosts: Set<String>,
         pageHeight: CGFloat,
         actions: ClaimCardActions) {
        self.claim = claim
        self.groupID = groupID
        self.timeZoneID = timeZoneID
        self.today = today
        self.isTest = isTest
        self.canVote = canVote
        self.failedPosts = failedPosts
        self.pageHeight = pageHeight
        self.actions = actions
    }

    private var tally: ClaimTally {
        claim.tally
    }

    /// A pending claim shows the state it would stand in.
    private var sphereState: SphereState {
        if tally.overruled {
            return .unlit
        }
        switch tally.kind {
        case .checkIn:
            return .lit
        case .excuse:
            return .excused
        }
    }

    /// Without voters (a solo group) there is no status line.
    private var status: String? {
        ChatText.status(tally, today: today, isTest: isTest)
    }

    private var hasVotes: Bool {
        tally.countsVotes + tally.againstVotes > 0
    }

    /// The vote buttons, which carry the counts: for a voter, or for anyone once someone has voted.
    private var showsVotes: Bool {
        canVote || hasVotes
    }

    var body: some View {
        card
            .accessibilityElement(children: .contain)
            .sensoryFeedback(.selection, trigger: claim.myVote)
    }

    @ViewBuilder
    private var card: some View {
        if claim.isCompact {
            compact
        } else {
            full
        }
    }

    // MARK: - Compact

    private var compact: some View {
        HStack(spacing: Gap.m) {
            sphere
            heading
            if canVote {
                CompactVote(onVote: actions.vote)
            }
        }
        .padding(.horizontal, Gap.l)
        .padding(.vertical, Gap.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Full

    private var full: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Gap.m) {
                sphere
                heading
            }
            if case .excuse(let text) = tally.kind {
                excuseBox(text)
                    .padding(.top, Gap.m)
                    .transition(.opacity)
            }
            if !claim.proofs.isEmpty {
                proofList
                    .padding(.top, Gap.m)
                    .transition(.opacity)
            }
            if let line: String = status {
                Hairline(leading: 0)
                    .padding(.horizontal, -Gap.l)
                    .padding(.top, Gap.l)
                if showsVotes {
                    VoteControl(choice: claim.myVote,
                                canVote: canVote,
                                canChange: claim.canChangeVote,
                                countsVotes: tally.countsVotes,
                                againstVotes: tally.againstVotes,
                                onVote: actions.vote)
                        .padding(.top, Gap.m)
                }
                statusRow(line)
                    .padding(.top, showsVotes ? 0 : Gap.xs)
                if showsVoters && hasVotes {
                    voterList
                        .padding(.bottom, Gap.s)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, Gap.l)
        .padding(.top, Gap.l)
        .padding(.bottom, status == nil ? Gap.l : Gap.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Header

    private var sphere: some View {
        Sphere(theme: Overview.theme(day: tally.day),
               state: sphereState,
               size: ClaimCard.sphereSize,
               initial: claim.initial,
               glows: false)
            .animation(Anim.light, value: sphereState)
    }

    /// Title over "{vow} · {time}" (the vow truncates, the time never), with "Overruled" beside the title,
    /// or under it at accessibility sizes. One VoiceOver element.
    private var heading: some View {
        VStack(alignment: .leading, spacing: Gap.xxs) {
            if typeSize.isAccessibilitySize {
                titleText
                if tally.overruled {
                    Tag("Overruled")
                }
            } else {
                HStack(spacing: Gap.s) {
                    titleText
                    if tally.overruled {
                        Spacer(minLength: Gap.s)
                        Tag("Overruled")
                            .fixedSize()
                    }
                }
            }
            subline
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChatText.spokenHeader(title: title,
                                                  time: tally.claimedAt == nil ? "Sending" : timeText,
                                                  vow: claim.vow,
                                                  overruled: tally.overruled))
    }

    private var title: String {
        ChatText.title(name: claim.name, isMine: claim.isMine, kind: tally.kind)
    }

    private var titleText: some View {
        Text(title)
            .font(Fonts.subheadlineSemibold)
            .foregroundStyle(Ink.text)
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
    }

    /// "8:02 AM", or "Sending…" while the claim saves.
    private var timeText: String {
        guard let at: Date = tally.claimedAt else { return ChatText.sending }
        return DayText.time(at, timeZoneID: timeZoneID)
    }

    private var subline: some View {
        HStack(spacing: 0) {
            if !claim.vow.isEmpty {
                Text(claim.vow)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(" · ")
                    .fixedSize()
            }
            Text(timeText)
                .fixedSize()
        }
        .font(Fonts.footnote)
        .foregroundStyle(Ink.text2)
    }

    private func excuseBox(_ text: String) -> some View {
        Text(text)
            .font(Fonts.subheadline)
            .foregroundStyle(Ink.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Gap.m)
            .padding(.vertical, Gap.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Corner.field, style: .continuous).fill(Ink.field))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Excuse: " + text)
    }

    // MARK: - Proof

    /// Every proof for the claim, oldest first, each with its caption. One proof may stand tall; several
    /// share the space. Both stay within the page (about 225 and 175 pt on an iPhone SE).
    private var proofList: some View {
        let single: Bool = claim.proofs.count == 1
        let maxHeight: CGFloat = single ? min(360, 0.45 * pageHeight) : min(240, 0.35 * pageHeight)
        return VStack(alignment: .leading, spacing: Gap.s) {
            ForEach(claim.proofs) { (post: PostInfo) in
                proofItem(post, maxHeight: maxHeight)
            }
        }
    }

    private func proofItem(_ post: PostInfo, maxHeight: CGFloat) -> some View {
        let caption: String = post.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 0) {
            PostMediaView(post: post, groupID: groupID, maxHeight: maxHeight)
                .onTapGesture {
                    actions.openMedia(post.id)
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens full screen")
                .accessibilityAction {
                    actions.openMedia(post.id)
                }
            if !caption.isEmpty {
                Text(caption)
                    .font(Fonts.subheadline)
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Gap.s)
                    .accessibilityHidden(true)
            }
            if failedPosts.contains(post.id) {
                ChatFailedRow(onRetry: { actions.retry(post.id) }, onDelete: { actions.discard(post.id) })
            }
        }
    }

    // MARK: - Votes

    /// The whole row is the button that shows who voted, once anyone has; until then it is plain text. Its
    /// 44 pt height supplies the card's bottom margin.
    @ViewBuilder
    private func statusRow(_ line: String) -> some View {
        if hasVotes {
            Button {
                withAnimation(reduceMotion ? nil : Anim.standard) {
                    showsVoters.toggle()
                }
            } label: {
                statusLine(line, chevron: true)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(ChatText.spoken(line))
            .accessibilityHint(showsVoters ? "Hides who voted" : "Shows who voted")
        } else {
            statusLine(line, chevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ChatText.spoken(line))
        }
    }

    private func statusLine(_ line: String, chevron: Bool) -> some View {
        HStack(spacing: Gap.s) {
            Text(line)
                .font(Fonts.footnote)
                .foregroundStyle(Ink.text3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Gap.s)
            if chevron {
                Image(systemName: showsVoters ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.text3)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Gap.hit, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Everyone who voted, you first: votes are visible to the group, and nobody who hasn't voted is named.
    private var voterList: some View {
        VStack(spacing: 0) {
            ForEach(claim.voters) { (voter: ChatVoter) in
                HStack(spacing: Gap.m) {
                    ChatAvatar(initial: voter.initial, size: 22)
                    Text(voter.name)
                        .font(voter.isYou ? Fonts.footnoteSemibold : Fonts.footnote)
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                    Spacer(minLength: Gap.s)
                    Image(systemName: voter.counts ? "checkmark" : "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(VoteControl.tint(voter.counts))
                    Text(ChatText.vote(voter.counts))
                        .font(Fonts.footnote)
                        .foregroundStyle(Ink.text2)
                }
                .frame(minHeight: 30)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(voter.name)
                .accessibilityValue(ChatText.vote(voter.counts))
            }
        }
    }
}

/// A compact card's two round buttons, the green checkmark and the red ✕. A tap votes, and the card opens
/// with your choice filled.
struct CompactVote: View {
    let onVote: (Bool) -> Void

    init(onVote: @escaping (Bool) -> Void) {
        self.onVote = onVote
    }

    var body: some View {
        HStack(spacing: Gap.s) {
            disc(counts: true, symbol: "checkmark", size: 14)
            disc(counts: false, symbol: "xmark", size: 12)
        }
    }

    private func disc(counts: Bool, symbol: String, size: CGFloat) -> some View {
        Button {
            onVote(counts)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(VoteControl.tint(counts))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Ink.field))
                .frame(width: Gap.hit, height: Gap.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(ChatText.vote(counts))
    }
}

/// "Counts" and "Doesn't count" on a full card, each with its number of votes just before it and a wider gap
/// before the second number, so "2 ✓ Counts   1 ✕ Doesn't count" can't be misread. The checkmark is green
/// and the ✕ red; your vote fills its whole button with that colour. Tapping your choice again does nothing,
/// and in voting's last half hour the other is off: only a first vote is taken then. Without a vote to cast
/// (your own claim, a day you don't take part in, voting closed) the buttons only show the counts: outlined,
/// with your past vote still filled. They stack when the row doesn't fit.
struct VoteControl: View {
    /// Your vote; nil before you have voted.
    let choice: Bool?
    /// You may vote on this claim now: one of its voters, a member, and voting is open.
    let canVote: Bool
    /// A vote you have cast may still change (`Review.canChangeVote`).
    let canChange: Bool
    let countsVotes: Int
    let againstVotes: Int
    let onVote: (Bool) -> Void

    /// The numbers' column when the buttons stack, so their leading edges line up.
    @ScaledMetric(relativeTo: .subheadline) private var countWidth: CGFloat = 18

    init(choice: Bool?,
         canVote: Bool,
         canChange: Bool,
         countsVotes: Int,
         againstVotes: Int,
         onVote: @escaping (Bool) -> Void) {
        self.choice = choice
        self.canVote = canVote
        self.canChange = canChange
        self.countsVotes = countsVotes
        self.againstVotes = againstVotes
        self.onVote = onVote
    }

    /// A choice's glyph on a neutral button: green for "Counts", red for "Doesn't count".
    static func tint(_ counts: Bool) -> Color {
        return counts ? Ink.voteCounts : Ink.voteAgainst
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Gap.xl) {
                option(counts: true, stacked: false)
                option(counts: false, stacked: false)
            }
            VStack(alignment: .leading, spacing: 0) {
                option(counts: true, stacked: true)
                option(counts: false, stacked: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The number, then its button.
    private func option(counts: Bool, stacked: Bool) -> some View {
        HStack(spacing: Gap.s) {
            count(counts ? countsVotes : againstVotes, stacked: stacked)
            button(counts: counts, stacked: stacked)
        }
    }

    /// Quiet at zero.
    private func count(_ n: Int, stacked: Bool) -> some View {
        Text("\(n)")
            .font(Fonts.numberSmall)
            .monospacedDigit()
            .foregroundStyle(n > 0 ? Ink.text : Ink.text3)
            .frame(minWidth: stacked ? countWidth : nil, alignment: .trailing)
            .accessibilityHidden(true)
    }

    private func button(counts: Bool, stacked: Bool) -> some View {
        let chosen: Bool = choice == counts
        let open: Bool = canVote && (chosen || choice == nil || canChange)
        let locked: Bool = canVote && !open
        return Button {
            if !chosen {
                onVote(counts)
            }
        } label: {
            HStack(spacing: Gap.xs) {
                Image(systemName: counts ? "checkmark" : "xmark")
                    .font(.system(size: counts ? 13 : 11, weight: .bold))
                    .foregroundStyle(chosen ? Ink.text : VoteControl.tint(counts))
                    .accessibilityHidden(true)
                Text(ChatText.vote(counts))
                    .font(chosen ? Fonts.subheadlineSemibold : Fonts.subheadlineMedium)
                    .foregroundStyle(chosen || open ? Ink.text : Ink.text2)
            }
            .padding(.horizontal, Gap.m)
            .frame(maxWidth: stacked ? CGFloat.infinity : nil, minHeight: 36)
            .background(face(counts: counts, chosen: chosen, open: open))
            .padding(.vertical, Gap.xs)
            .contentShape(Rectangle())
            .animation(Anim.press, value: chosen)
        }
        .buttonStyle(PressStyle())
        .disabled(!open)
        .accessibilityLabel(ChatText.vote(counts))
        .accessibilityValue(ChatText.voteCount(counts ? countsVotes : againstVotes))
        .accessibilityHint(locked ? ChatText.voteLocked : "")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Your vote filled with its colour; a choice you can make on the field colour; one you can't, outlined.
    @ViewBuilder
    private func face(counts: Bool, chosen: Bool, open: Bool) -> some View {
        if chosen {
            Capsule()
                .fill(counts ? Ink.voteCountsFill : Ink.voteAgainstFill)
        } else if open {
            Capsule()
                .fill(Ink.field)
        } else {
            Capsule()
                .strokeBorder(Ink.chip, lineWidth: 1)
        }
    }
}
