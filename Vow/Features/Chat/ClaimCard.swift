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
/// "Overruled". Votes are neutral: your choice is outlined, never coloured, because a vote isn't points.
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
                if canVote {
                    VoteControl(choice: claim.myVote, canChange: claim.canChangeVote, onVote: actions.vote)
                        .padding(.top, Gap.m)
                }
                statusRow(line)
                    .padding(.top, canVote ? 0 : Gap.xs)
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

/// A compact card's two round buttons. A tap votes, and the card opens with your choice outlined.
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
                .foregroundStyle(Ink.text)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Ink.field))
                .frame(width: Gap.hit, height: Gap.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(ChatText.vote(counts))
    }
}

/// "Counts" and "Doesn't count" on a full card: neutral capsules, your choice filled and outlined (never
/// white, so a past vote is never the loudest thing on the card). Tapping your choice again does nothing,
/// and in voting's last half hour the other is off: only a first vote is taken then. They stack at
/// accessibility sizes.
struct VoteControl: View {
    /// Your vote; nil before you have voted.
    let choice: Bool?
    /// A vote you have cast may still change (`Review.canChangeVote`).
    let canChange: Bool
    let onVote: (Bool) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize: DynamicTypeSize

    init(choice: Bool?, canChange: Bool, onVote: @escaping (Bool) -> Void) {
        self.choice = choice
        self.canChange = canChange
        self.onVote = onVote
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                capsule(counts: true)
                capsule(counts: false)
            }
        } else {
            HStack(spacing: Gap.s) {
                capsule(counts: true)
                capsule(counts: false)
            }
        }
    }

    private func capsule(counts: Bool) -> some View {
        let chosen: Bool = choice == counts
        let locked: Bool = !chosen && choice != nil && !canChange
        return Button {
            if !chosen {
                onVote(counts)
            }
        } label: {
            HStack(spacing: Gap.xs) {
                Image(systemName: counts ? "checkmark" : "xmark")
                    .font(.system(size: counts ? 13 : 11, weight: .bold))
                    .accessibilityHidden(true)
                Text(ChatText.vote(counts))
                    .font(chosen ? Fonts.subheadlineSemibold : Fonts.subheadlineMedium)
            }
            .foregroundStyle(chosen ? Ink.text : Ink.text2)
            .opacity(locked ? 0.35 : 1)
            .padding(.horizontal, 14)
            .frame(maxWidth: typeSize.isAccessibilitySize ? CGFloat.infinity : nil, minHeight: 36)
            .background(face(chosen))
            .padding(.vertical, Gap.xs)
            .contentShape(Rectangle())
            .animation(Anim.press, value: chosen)
        }
        .buttonStyle(PressStyle())
        .disabled(locked)
        .accessibilityLabel(ChatText.vote(counts))
        .accessibilityHint(locked ? ChatText.voteLocked : "")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func face(_ chosen: Bool) -> some View {
        Capsule()
            .fill(chosen ? Ink.chip : Ink.field)
            .overlay(Capsule().strokeBorder(Ink.text, lineWidth: 1.5).opacity(chosen ? 1 : 0))
    }
}
