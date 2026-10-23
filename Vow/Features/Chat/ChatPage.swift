import Combine
import SwiftUI
import UIKit

/// Callbacks from Chat to the shell, which owns every sheet and cover.
struct ChatActions {
    /// "+" → Take photo or video: the camera, for proof.
    let takeProof: () -> Void
    /// "+" → Choose from library: the photo library, for proof.
    let pickProof: () -> Void
    /// "+" → Excuse for today.
    let excuse: () -> Void
    /// A tap on proof: the media viewer, by post id.
    let openMedia: (String) -> Void
    /// "Write your vow to join", for someone who isn't a member yet. Never offered for a finished vow.
    let join: () -> Void
    /// The page holds the touch for itself (true) or lets it go: while the "+" card or the reaction picker is
    /// up, or while you type, the shell's swipes between tabs stand down, so a drag across a scrim, or one
    /// that moves the cursor or selects text, never moves the page.
    let overlay: (Bool) -> Void
}

/// The Chat tab: the group's messages, one card per check-in or excuse with its proof and votes, and the
/// composer. The latest is at the bottom, where the page opens and where re-tapping the tab returns; the
/// week up to the newest item shows until Earlier is tapped. There is no pull to refresh, since the top is
/// history: the shell polls while Chat is shown, the page refreshes on appear and after your votes, and the
/// store refreshes after your other sends. The chat is marked seen on appear, on every change and on
/// leaving, so the tab's dot never lights for what you are reading. Chat presents nothing itself; it asks the
/// shell through `actions`. Its own two overlays, the "+" card and the reaction picker, close when the sidebar
/// covers the page. The shell ignores the keyboard, so the page lifts its own composer.
struct ChatPage: View {
    let id: GroupID
    /// Bumped when the Chat tab is tapped again: scroll to the latest.
    let topToken: Int
    /// The group's unsent message, kept by the shell across tab and group switches.
    @Binding var draft: String
    /// Something covers the page (the sidebar): the "+" card and the reaction picker close, as they would
    /// for a tap outside them.
    let covered: Bool
    let actions: ChatActions

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var memo: ChatFeedMemo = ChatFeedMemo()
    /// Earlier was tapped: the whole epoch shows, for as long as the page stays.
    @State private var showsAll: Bool = false
    /// The bottom of the feed is on screen: new content follows it, and the jump button hides.
    @State private var atBottom: Bool = true
    /// The feed has made its opening scroll to the bottom. Closing a cover shows the feed again, and that
    /// must leave you where you were.
    @State private var hasOpened: Bool = false
    @State private var plusOpen: Bool = false
    /// The message a long press opened the reaction picker over.
    @State private var reactingID: String? = nil
    /// The keyboard's top edge in global coordinates while it is up.
    @State private var keyboardTop: CGFloat? = nil
    /// How far the composer rides up over the keyboard, which covers the tab bar.
    @State private var lift: CGFloat = 0
    @FocusState private var composerFocused: Bool

    static let bottomID: String = "chat-bottom"
    private static let hasCamera: Bool = UIImagePickerController.isSourceTypeAvailable(.camera)
    /// The keyboard's animation when its notification doesn't give one.
    private static let keyboardSeconds: Double = 0.25
    private static let keyboardChanges: NotificationCenter.Publisher =
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
    private static let keyboardHides: NotificationCenter.Publisher =
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)

    init(id: GroupID, topToken: Int, draft: Binding<String>, covered: Bool, actions: ChatActions) {
        self.id = id
        self.topToken = topToken
        self._draft = draft
        self.covered = covered
        self.actions = actions
    }

    /// The page keeps its drags from the shell's tab swipes (`ChatActions.overlay`): the "+" card or the
    /// reaction picker is up, or you are typing.
    private var holdsTouch: Bool {
        plusOpen || reactingID != nil || composerFocused
    }

    /// On a per-minute clock, so "Today" and when voting ends roll over on time.
    var body: some View {
        TimelineView(.everyMinute) { context in
            page(now: context.date)
        }
        .vowBackground()
        .onAppear {
            store.markChatSeen(id)
            actions.overlay(holdsTouch)
            Task {
                await store.refresh(id)
            }
        }
        .onDisappear {
            store.markChatSeen(id)
            actions.overlay(false)
        }
        .onChange(of: store.snapshots[id]) { _, _ in
            store.markChatSeen(id)
        }
        .onChange(of: covered) { (_: Bool, isCovered: Bool) in
            if isCovered {
                closePlus()
                closeReactions()
            }
        }
        .onChange(of: holdsTouch) { (_: Bool, holds: Bool) in
            actions.overlay(holds)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: reactingID) { (_: String?, held: String?) -> Bool in
            held != nil
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func page(now: Date) -> some View {
        if let snapshot: GroupSnapshot = store.snapshots[id] {
            loaded(snapshot, now: now)
        } else {
            ProgressView()
                .tint(Ink.text3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The page's size is read once: the shell ignores the keyboard, so it never changes while typing.
    private func loaded(_ snapshot: GroupSnapshot, now: Date) -> some View {
        let group: GroupInfo = snapshot.group
        let feed: ChatFeed = memo.feed(snapshot, viewerID: store.userID ?? "", now: now, showsAll: showsAll)
        let isMember: Bool = store.myMember(id).map { (me: MemberInfo) -> Bool in me.leftDay == nil } ?? false
        let failedPosts: Set<String> = store.failedPosts
        return GeometryReader { (geometry: GeometryProxy) in
            ScrollViewReader { (proxy: ScrollViewProxy) in
                screen(feed,
                       context: ChatContext(group: group,
                                            today: DayClock.currentDay(group, now: now),
                                            now: now,
                                            isMember: isMember,
                                            isFinished: EndDate.isFinished(group, now: now),
                                            failedPosts: failedPosts,
                                            size: geometry.size,
                                            maxY: geometry.frame(in: .global).maxY),
                       proxy: proxy)
            }
        }
    }

    /// The feed, and the composer (or the join bar) under it. The feed ends at the bar rather than scrolling
    /// behind it, so the bottom counts as in view only when it is, with the keyboard up too. The fade, the
    /// jump button and the "+" card (over its scrim) sit at the feed's bottom edge, which is the bar's top,
    /// so they ride the keyboard and the field's growth and never cover the bar. The reaction picker covers
    /// the whole page.
    private func screen(_ feed: ChatFeed, context: ChatContext, proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            feedArea(feed, context: context, proxy: proxy)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    fade
                }
                .overlay(alignment: .bottomTrailing) {
                    jumpButton(visible: !atBottom && !plusOpen && !feed.isEmpty, proxy: proxy)
                }
                .overlay {
                    scrim
                }
                .overlay(alignment: .bottomLeading) {
                    if plusOpen {
                        plusCard(feed, context: context)
                    }
                }
            bar(context)
                .padding(.bottom, lift)
        }
        .overlayPreferenceValue(ReactionAnchorKey.self, alignment: .topLeading) { (anchor: Anchor<CGRect>?) in
            GeometryReader { (geometry: GeometryProxy) in
                if let target: ReactionTarget = reactionTarget(feed, anchor: anchor, geometry: geometry) {
                    reactionScrim(target)
                    reactionPicker(target, page: geometry.size)
                }
            }
        }
        .onReceive(ChatPage.keyboardChanges) { (note: Notification) in
            keyboardWillChange(note, hiding: false, maxY: context.maxY, proxy: proxy)
        }
        .onReceive(ChatPage.keyboardHides) { (note: Notification) in
            keyboardWillChange(note, hiding: true, maxY: context.maxY, proxy: proxy)
        }
        .onChange(of: composerFocused) { (_: Bool, focused: Bool) in
            if focused {
                closePlus()
            }
            updateLift(maxY: context.maxY, seconds: ChatPage.keyboardSeconds, proxy: proxy)
        }
        .onChange(of: topToken) { _, _ in
            scrollToBottom(proxy, animated: true)
        }
        .onChange(of: lostHeld(feed)) { (_: Bool, lost: Bool) in
            if lost {
                closeReactions()
            }
        }
    }

    @ViewBuilder
    private func feedArea(_ feed: ChatFeed, context: ChatContext, proxy: ScrollViewProxy) -> some View {
        if feed.isEmpty {
            emptyState(hasVoters: feed.hasVoters)
        } else {
            scroller(feed, context: context, proxy: proxy)
        }
    }

    // MARK: - Feed

    /// Opens at the bottom (`OpensAtBottom`). iOS 17's estimates for a lazy stack can leave the first scroll
    /// short, so it scrolls to the bottom once more after the first layout, once per page. New content
    /// follows the bottom only while it is in view, or when it is your own; otherwise the jump button shows.
    private func scroller(_ feed: ChatFeed, context: ChatContext, proxy: ScrollViewProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if feed.hasEarlier {
                    earlierButton(feed, proxy: proxy)
                }
                if feed.hasVoters {
                    preamble(context)
                }
                ForEach(feed.rows) { (row: ChatRow) in
                    rowView(row, context: context, proxy: proxy)
                        .padding(.top, ChatPage.space(row.gap))
                        .transition(arrival)
                }
                bottomSentinel
            }
            .padding(.horizontal, Gap.gutter)
            .padding(.bottom, Gap.m)
            .animation(reduceMotion ? Anim.fade : Anim.standard, value: feed.rows.count)
            .animation(reduceMotion ? nil : Anim.standard, value: feed.shape)
        }
        .modifier(OpensAtBottom())
        .scrollDismissesKeyboard(.immediately)
        .onAppear {
            guard !hasOpened else { return }
            hasOpened = true
            Task {
                await Task.yield()
                proxy.scrollTo(ChatPage.bottomID, anchor: .bottom)
            }
        }
        .onChange(of: feed.rows.last) { (_: ChatRow?, last: ChatRow?) in
            if atBottom || last?.isOwnPending == true {
                scrollToBottom(proxy, animated: true)
            }
        }
    }

    /// The feed's last child: on screen means the bottom is in view.
    private var bottomSentinel: some View {
        Color.clear
            .frame(height: 1)
            .id(ChatPage.bottomID)
            .onAppear {
                atBottom = true
            }
            .onDisappear {
                atBottom = false
            }
            .accessibilityHidden(true)
    }

    /// New rows fade in with a small rise; under Reduce Motion they only fade.
    private var arrival: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .offset(y: 8))
    }

    private static func space(_ gap: ChatGap) -> CGFloat {
        switch gap {
        case .none:
            return 0
        case .run:
            return Gap.xxs
        case .item:
            return Gap.m
        case .section:
            return Gap.l
        }
    }

    @ViewBuilder
    private func rowView(_ row: ChatRow, context: ChatContext, proxy: ScrollViewProxy) -> some View {
        switch row.content {
        case .day(let day):
            dayHeader(day, context: context)
        case .message(let message):
            bubble(message, context: context, proxy: proxy)
        case .claim(let claim):
            card(claim, context: context)
        case .pointer(let pointer):
            pointerRow(pointer, context: context, proxy: proxy)
        }
    }

    private func dayHeader(_ day: Int, context: ChatContext) -> some View {
        Text(ChatText.header(day: day, today: context.today, group: context.group, now: context.now))
            .font(Fonts.footnoteSemibold)
            .foregroundStyle(Ink.text3)
            .frame(maxWidth: .infinity)
            .padding(.bottom, Gap.s)
            .accessibilityAddTraits(.isHeader)
    }

    /// A member reacts to a message once it is sent (the store takes reactions to saved posts only).
    private func bubble(_ message: ChatMessage, context: ChatContext, proxy: ScrollViewProxy) -> some View {
        let postID: String = message.post.id
        let messageActions: MessageActions = MessageActions(
            retry: { retry(postID) },
            delete: { store.discardPost(postID, in: id) },
            showReactions: { openReactions(postID, proxy: proxy) },
            react: { (emoji: String?) in react(emoji, to: postID) }
        )
        return MessageBubble(message: message,
                             time: DayText.time(message.time, timeZoneID: context.group.timeZoneID),
                             failed: context.failedPosts.contains(postID),
                             maxWidth: context.size.width * 0.72,
                             canReact: context.isMember && message.post.serverDate != nil,
                             isReacting: reactingID == postID,
                             actions: messageActions)
    }

    private func card(_ claim: ChatClaim, context: ChatContext) -> some View {
        let tally: ClaimTally = claim.tally
        let cardActions: ClaimCardActions = ClaimCardActions(
            vote: { (counts: Bool) in vote(on: tally, counts: counts) },
            openMedia: actions.openMedia,
            retry: { (postID: String) in retry(postID) },
            discard: { (postID: String) in store.discardPost(postID, in: id) }
        )
        return ClaimCard(claim: claim,
                         groupID: id,
                         timeZoneID: context.group.timeZoneID,
                         today: context.today,
                         isTest: context.group.isTest,
                         canVote: claim.canVote && context.isMember,
                         failedPosts: context.failedPosts,
                         pageHeight: context.size.height,
                         actions: cardActions)
    }

    /// "Maya added proof to yesterday's check-in": a tap brings the card, which holds the photo, to the middle.
    private func pointerRow(_ pointer: ChatPointer, context: ChatContext, proxy: ScrollViewProxy) -> some View {
        let text: String = ChatText.pointer(name: pointer.author, isMine: pointer.isMine, claimDay: pointer.claimDay,
                                            isExcuse: pointer.isExcuse, today: context.today, group: context.group,
                                            now: context.now)
        return Button {
            withAnimation(reduceMotion ? nil : Anim.standard) {
                proxy.scrollTo(pointer.cardID, anchor: .center)
            }
        } label: {
            HStack(spacing: Gap.xs) {
                Image(systemName: "photo")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.text3)
                Text(text)
                    .font(Fonts.footnote)
                    .foregroundStyle(Ink.text2)
                    .multilineTextAlignment(.center)
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.text3)
            }
            .frame(maxWidth: .infinity, minHeight: Gap.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(text)
        .accessibilityHint(pointer.isExcuse ? "Shows the excuse" : "Shows the check-in")
    }

    /// The group's rule for today, in words, above everything once there is someone to overrule a claim.
    private func preamble(_ context: ChatContext) -> some View {
        Text(VoteRuleText.summary(Review.rule(forDay: context.today, group: context.group)))
            .font(Fonts.footnote)
            .foregroundStyle(Ink.text3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Gap.xxl)
            .padding(.top, Gap.m)
            .padding(.bottom, Gap.xs)
            .frame(maxWidth: .infinity)
    }

    private func earlierButton(_ feed: ChatFeed, proxy: ScrollViewProxy) -> some View {
        Button {
            showEarlier(keeping: feed.rows.first?.id, proxy: proxy)
        } label: {
            HStack(spacing: Gap.xs) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.text3)
                Text("Earlier")
                    .font(Fonts.footnoteSemibold)
                    .foregroundStyle(Ink.text2)
            }
            .frame(maxWidth: .infinity, minHeight: Gap.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Earlier")
    }

    // MARK: - Empty

    /// Centred above the composer; it scrolls only when it can't fit (accessibility sizes with the keyboard up).
    private func emptyState(hasVoters: Bool) -> some View {
        ViewThatFits(in: .vertical) {
            emptyMessage(hasVoters: hasVoters)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView(.vertical, showsIndicators: false) {
                emptyMessage(hasVoters: hasVoters)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Gap.xxl)
            }
        }
    }

    private func emptyMessage(hasVoters: Bool) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24))
                .foregroundStyle(Ink.text2)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Ink.field))
                .accessibilityHidden(true)
            Text("Nothing here yet")
                .font(Fonts.headline)
                .foregroundStyle(Ink.text)
                .padding(.top, 14)
            Text(ChatText.emptyBody(hasVoters: hasVoters))
                .font(Fonts.subheadline)
                .foregroundStyle(Ink.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Gap.s)
        }
        .frame(maxWidth: 300)
        .padding(.horizontal, Gap.gutter)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Bottom bar

    /// The composer for members (a finished vow's chat stays open), the join bar for someone who isn't one
    /// yet, or a closing line once the vow has ended.
    @ViewBuilder
    private func bar(_ context: ChatContext) -> some View {
        if context.isMember {
            ChatComposer(draft: $draft,
                         focus: $composerFocused,
                         plusOpen: plusOpen,
                         onPlus: togglePlus,
                         onSend: send)
        } else if context.isFinished {
            Text("This vow has ended.")
                .font(Fonts.footnote)
                .foregroundStyle(Ink.text3)
                .frame(maxWidth: .infinity, minHeight: Gap.control)
                .background(Ink.bg)
        } else {
            PillButton("Write your vow to join", action: actions.join)
                .padding(.horizontal, Gap.gutter)
                .padding(.vertical, Gap.s)
                .background(Ink.bg)
        }
    }

    /// The feed fades out just above the bar.
    private var fade: some View {
        LinearGradient(colors: [Ink.bg.opacity(0), Ink.bg], startPoint: .top, endPoint: .bottom)
            .frame(height: Gap.l)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// A 36 pt disc 16 pt from the trailing edge and 12 pt above the bar, in a 44 pt target.
    private func jumpButton(visible: Bool, proxy: ScrollViewProxy) -> some View {
        Button {
            scrollToBottom(proxy, animated: true)
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Ink.text)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Ink.toast).shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .frame(width: Gap.hit, height: Gap.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Latest messages")
        .padding(.trailing, Gap.m)
        .padding(.bottom, Gap.s)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .animation(Anim.fade, value: visible)
    }

    /// 8 pt above the composer, from x = 16 (clear of the shell's edge swipe). It is laid out in the space
    /// the feed leaves above the bar, at its own height, so it always fits on screen whole; at large text
    /// sizes on a small screen it scrolls inside.
    private func plusCard(_ feed: ChatFeed, context: ChatContext) -> some View {
        ChatPlusMenu(header: ChatText.plusHeader(proofDay: feed.proofDay, kind: feed.proofKind, today: context.today,
                                                 isFinished: context.isFinished),
                     canAddProof: feed.proofDay != nil,
                     hasCamera: ChatPage.hasCamera,
                     excuseNote: ChatText.excuseNote(store.excuseBlock(id, now: context.now)),
                     onTakeProof: { pick(actions.takeProof) },
                     onPickProof: { pick(actions.pickProof) },
                     onExcuse: { pick(actions.excuse) },
                     onClose: closePlus)
            .frame(width: min(280, max(0, context.size.width - 2 * Gap.l)))
            .padding(.leading, Gap.l)
            .padding(.vertical, Gap.s)
            .transition(plusTransition)
    }

    /// The card grows from its corner by the "+"; under Reduce Motion it only fades.
    private var plusTransition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading))
    }

    // MARK: - Reactions

    /// The held message and its bounds on the page, while the picker is open and the message is shown.
    private func reactionTarget(_ feed: ChatFeed, anchor: Anchor<CGRect>?, geometry: GeometryProxy) -> ReactionTarget? {
        guard let postID: String = reactingID,
              let bounds: Anchor<CGRect> = anchor,
              let message: ChatMessage = feed.message(postID) else { return nil }
        return ReactionTarget(message: message, frame: geometry[bounds])
    }

    /// The picker is open over a message the feed no longer shows (a refresh took it away): it closes.
    private func lostHeld(_ feed: ChatFeed) -> Bool {
        guard let postID: String = reactingID else { return false }
        return feed.message(postID) == nil
    }

    /// Over the whole page, the bar included, with the held bubble left clear. A tap anywhere but the picker
    /// closes it.
    private func reactionScrim(_ target: ReactionTarget) -> some View {
        ScrimCutout(hole: target.frame, bubble: MessageBubble.shape(for: target.message))
            .fill(Ink.scrim, style: FillStyle(eoFill: true))
            .contentShape(Rectangle())
            .onTapGesture {
                closeReactions()
            }
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    /// Just above the held bubble (below it when there is no room above), in line with its edge. It grows
    /// from the side that faces the bubble; under Reduce Motion it only fades.
    private func reactionPicker(_ target: ReactionTarget, page: CGSize) -> some View {
        let message: ChatMessage = target.message
        let cell: CGFloat = ReactionPicker.cell(forWidth: page.width - 2 * Gap.s)
        let size: CGSize = ReactionPicker.size(cell: cell)
        let place: ReactionPlace = ReactionPicker.place(size, by: target.frame, alignTrailing: message.isMine, in: page)
        let facing: CGFloat = place.above ? place.origin.y + size.height : place.origin.y
        let grows: UnitPoint = UnitPoint(x: (place.origin.x + size.width / 2) / max(page.width, 1),
                                         y: facing / max(page.height, 1))
        return ReactionPicker(mine: message.myReaction,
                              cell: cell,
                              onReact: { (emoji: String?) in react(emoji, to: message.post.id) },
                              onCopy: { copy(message) },
                              onClose: closeReactions)
            .frame(width: size.width, height: size.height)
            .padding(.leading, place.origin.x)
            .padding(.top, place.origin.y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(reduceMotion ? AnyTransition.opacity
                                     : AnyTransition.opacity.combined(with: .scale(scale: 0.85, anchor: grows)))
    }

    /// Over the feed only, while the "+" card is open: a tap closes the card.
    @ViewBuilder
    private var scrim: some View {
        if plusOpen {
            Ink.scrim
                .contentShape(Rectangle())
                .onTapGesture {
                    closePlus()
                }
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Actions

    /// "+" ends editing first, so the card never opens under the keyboard.
    private func togglePlus() {
        composerFocused = false
        withAnimation(Anim.standard) {
            plusOpen.toggle()
        }
    }

    private func closePlus() {
        guard plusOpen else { return }
        withAnimation(Anim.standard) {
            plusOpen = false
        }
    }

    /// A long press on a message: the keyboard and the "+" card go, the message scrolls the least it takes to
    /// show whole (never under the bar, where the scrim's cut-out would lay the composer bare), and the picker
    /// opens over it.
    private func openReactions(_ postID: String, proxy: ScrollViewProxy) {
        composerFocused = false
        closePlus()
        withAnimation(reduceMotion ? nil : Anim.standard) {
            proxy.scrollTo(postID)
        }
        withAnimation(reduceMotion ? Anim.fade : Anim.standard) {
            reactingID = postID
        }
    }

    private func closeReactions() {
        guard reactingID != nil else { return }
        withAnimation(reduceMotion ? Anim.fade : Anim.standard) {
            reactingID = nil
        }
    }

    /// From the picker or a chip: an emoji, or nil to take yours back. The store shows it at once and puts
    /// back the one it replaced if the save fails.
    private func react(_ emoji: String?, to postID: String) {
        closeReactions()
        Task {
            await store.react(emoji, to: postID, in: id)
        }
    }

    private func copy(_ message: ChatMessage) {
        UIPasteboard.general.string = message.post.text
        closeReactions()
    }

    /// Closes the card, then asks the shell for the camera, the library or the excuse sheet.
    private func pick(_ action: () -> Void) {
        closePlus()
        action()
    }

    /// The store shows the message at once (your own pending row brings the feed to the bottom) and refreshes
    /// once it is saved.
    private func send(_ text: String) {
        Task {
            await store.sendMessage(text, in: id)
        }
    }

    /// Votes, then refreshes, so votes cast meanwhile show at once. A failed vote reverts with a toast.
    private func vote(on tally: ClaimTally, counts: Bool) {
        Task {
            await store.vote(subject: tally.subject, day: tally.day, counts: counts, in: id)
            await store.refresh(id)
        }
    }

    private func retry(_ postID: String) {
        Task {
            await store.retryPost(postID, in: id)
        }
    }

    // MARK: - Scrolling

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        withAnimation(animated && !reduceMotion ? Anim.standard : nil) {
            proxy.scrollTo(ChatPage.bottomID, anchor: .bottom)
        }
    }

    /// Loads the rest of the epoch without animation, then puts the row that was first back at the top, so
    /// what you were reading doesn't jump.
    private func showEarlier(keeping firstID: String?, proxy: ScrollViewProxy) {
        withTransaction(ChatPage.still()) {
            showsAll = true
        }
        guard let anchor: String = firstID else { return }
        Task {
            await Task.yield()
            withTransaction(ChatPage.still()) {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }

    /// A change that animates nothing, whatever the views' own animations say.
    private static func still() -> Transaction {
        var transaction: Transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }

    // MARK: - Keyboard

    private func keyboardWillChange(_ note: Notification, hiding: Bool, maxY: CGFloat, proxy: ScrollViewProxy) {
        let info: [AnyHashable: Any] = note.userInfo ?? [:]
        let frame: CGRect? = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        let given: Double? = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue
        keyboardTop = hiding ? nil : frame?.minY
        updateLift(maxY: maxY, seconds: given ?? ChatPage.keyboardSeconds, proxy: proxy)
    }

    /// The composer rides on the keyboard only while its own field has focus, so a sheet's keyboard never
    /// moves it. If the bottom of the feed was in view, it stays in view.
    private func updateLift(maxY: CGFloat, seconds: Double, proxy: ScrollViewProxy) {
        var target: CGFloat = 0
        if composerFocused, let top: CGFloat = keyboardTop {
            target = max(0, maxY - top)
        }
        guard target != lift else { return }
        let follows: Bool = atBottom
        withAnimation(.easeOut(duration: seconds)) {
            lift = target
            if follows {
                proxy.scrollTo(ChatPage.bottomID, anchor: .bottom)
            }
        }
    }
}

/// The message the reaction picker is open over, and its bubble's bounds on the page.
private struct ReactionTarget {
    let message: ChatMessage
    let frame: CGRect
}

/// What every row needs to know about the page, worked out once per render.
private struct ChatContext {
    let group: GroupInfo
    /// The group's clock day (a finished vow's keeps moving: its chat stays open).
    let today: Int
    let now: Date
    /// An active member: the composer, and votes on the days you take part in.
    let isMember: Bool
    let isFinished: Bool
    let failedPosts: Set<String>
    /// The page, between the top bar and the tab bar.
    let size: CGSize
    /// The page's bottom edge in global coordinates, for the keyboard lift.
    let maxY: CGFloat
}

/// The feed, rebuilt only when the snapshot, you, the minute or the range changes, so typing or an upload's
/// progress never counts the votes again.
private final class ChatFeedMemo {
    private var key: Key? = nil
    private var value: ChatFeed? = nil

    func feed(_ snapshot: GroupSnapshot, viewerID: String, now: Date, showsAll: Bool) -> ChatFeed {
        let next: Key = Key(snapshot: snapshot, viewerID: viewerID, now: now, showsAll: showsAll)
        if let cached: ChatFeed = value, key == next {
            return cached
        }
        let built: ChatFeed = ChatFeed.build(snapshot, viewerID: viewerID, now: now, showAll: showsAll)
        key = next
        value = built
        return built
    }

    private struct Key: Equatable {
        let snapshot: GroupSnapshot
        let viewerID: String
        let now: Date
        let showsAll: Bool
    }
}

/// Opens the feed at its bottom. On iOS 17 the one anchor also pins size changes to the bottom, so a card
/// opening up or a new message moves everything above it while you are scrolled up; iOS 18 lets it set the
/// opening position alone. Following the bottom is left to the page's own scrolls.
private struct OpensAtBottom: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.defaultScrollAnchor(.bottom, for: .initialOffset)
        } else {
            content.defaultScrollAnchor(.bottom)
        }
    }
}
