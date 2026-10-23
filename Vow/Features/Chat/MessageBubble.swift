import SwiftUI
import UIKit

/// What a message asks of the page.
struct MessageActions {
    /// A failed message of yours: send it again, or delete it.
    let retry: () -> Void
    let delete: () -> Void
    /// A long press: the page's reaction picker over this message.
    let showReactions: () -> Void
    /// Your reaction: an emoji, or nil to take yours back.
    let react: (String?) -> Void
}

/// One text message. Others' runs lead with a name line, set where their text starts, and end with a letter
/// disc (a disc, not a Sphere: a Sphere's light means "kept today"); yours sit on the trailing side under
/// their time. The last bubble of a run has a tail on its sender's side. Reactions sit under the bubble as
/// chips. A member holds a sent message to react (the page's picker, which also copies) and taps a chip to
/// toggle theirs; a message still sending or not sent, or anyone who isn't a member, gets Copy from a
/// context menu instead. A message that is sending is faded; one that failed stays at full strength with
/// "Not sent · Retry · Delete" under it.
struct MessageBubble: View {
    let message: ChatMessage
    /// The message's time in the group's time zone: "8:21 PM".
    let time: String
    let failed: Bool
    /// 72 % of the page's width.
    let maxWidth: CGFloat
    /// A member, and the message is sent: holding it reacts, and its chips toggle your reaction.
    let canReact: Bool
    /// The page's reaction picker is open over this message, which reports its bounds for it.
    let isReacting: Bool
    let actions: MessageActions

    private static let avatarSize: CGFloat = 28
    /// Between others' letter disc and the tail strip of their bubbles.
    private static let avatarGap: CGFloat = Gap.xs
    /// The text's inset inside the bubble's body.
    private static let textInsetH: CGFloat = Gap.m + Gap.xxs
    private static let textInsetV: CGFloat = Gap.s + Gap.xxs
    /// From the bubble's edge on its tail side to where its text starts: the name line and your time line up
    /// with the text, not with the bubble.
    private static let textEdge: CGFloat = BubbleShape.tailWidth + textInsetH

    init(message: ChatMessage,
         time: String,
         failed: Bool,
         maxWidth: CGFloat,
         canReact: Bool,
         isReacting: Bool,
         actions: MessageActions) {
        self.message = message
        self.time = time
        self.failed = failed
        self.maxWidth = maxWidth
        self.canReact = canReact
        self.isReacting = isReacting
        self.actions = actions
    }

    /// The bubble's outline, tail included: the page's scrim leaves this shape clear while the picker is open.
    static func shape(for message: ChatMessage) -> BubbleShape {
        return BubbleShape(side: message.isMine ? .trailing : .leading, hasTail: message.endsRun)
    }

    private var sending: Bool {
        message.post.serverDate == nil && !failed
    }

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((message.isMine ? "You" : message.author) + ", " + message.post.text)
            .accessibilityValue(ChatText.messageValue(time: time, sending: sending, failed: failed,
                                                      reactions: message.reactions))
            .accessibilityActions {
                Button("Copy", action: copy)
                if canReact {
                    ForEach(Reactions.choices, id: \.self) { (emoji: String) in
                        Button(ChatText.reactAction(emoji, isMine: emoji == message.myReaction)) {
                            actions.react(emoji == message.myReaction ? nil : emoji)
                        }
                    }
                }
                if failed {
                    Button("Retry", action: actions.retry)
                    Button("Delete", action: actions.delete)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if message.isMine {
            yours
        } else {
            theirs
        }
    }

    // MARK: - Runs

    private var yours: some View {
        VStack(alignment: .trailing, spacing: Gap.xs) {
            if message.startsRun {
                Text(time)
                    .font(Fonts.footnote)
                    .foregroundStyle(Ink.text3)
                    .padding(.trailing, MessageBubble.textEdge)
            }
            bubble
            if !message.reactions.isEmpty {
                chips
                    .padding(.trailing, BubbleShape.tailWidth)
            }
            if failed {
                ChatFailedRow(onRetry: actions.retry, onDelete: actions.delete)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var theirs: some View {
        VStack(alignment: .leading, spacing: Gap.xs) {
            if message.startsRun {
                nameLine
                    .padding(.leading, MessageBubble.avatarSize + MessageBubble.avatarGap + MessageBubble.textEdge)
            }
            HStack(alignment: .bottom, spacing: MessageBubble.avatarGap) {
                if message.endsRun {
                    ChatAvatar(initial: message.initial, size: MessageBubble.avatarSize)
                } else {
                    Color.clear
                        .frame(width: MessageBubble.avatarSize, height: 0)
                }
                bubble
            }
            if !message.reactions.isEmpty {
                chips
                    .padding(.leading, MessageBubble.avatarSize + MessageBubble.avatarGap + BubbleShape.tailWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Maya · 8:20 PM".
    private var nameLine: some View {
        HStack(spacing: 0) {
            Text(message.author)
                .font(Fonts.footnoteSemibold)
                .foregroundStyle(Ink.text2)
                .lineLimit(1)
            Text(" · " + time)
                .font(Fonts.footnote)
                .foregroundStyle(Ink.text3)
                .fixedSize()
        }
    }

    /// Under the bubble, in line with its body.
    private var chips: some View {
        ReactionChips(reactions: message.reactions, canReact: canReact, onReact: actions.react)
            .padding(.top, Gap.xs)
    }

    // MARK: - Bubble

    /// The text with its inset, plus the tail strip on its sender's side, which every bubble of a run keeps
    /// so their bodies line up.
    private var bubble: some View {
        let shape: BubbleShape = MessageBubble.shape(for: message)
        return Text(message.post.text)
            .font(Fonts.body)
            .foregroundStyle(Ink.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, MessageBubble.textInsetH)
            .padding(.vertical, MessageBubble.textInsetV)
            .padding(message.isMine ? .trailing : .leading, BubbleShape.tailWidth)
            .background(fill(shape))
            .modifier(BubblePress(canReact: canReact, shape: shape, onHold: actions.showReactions, onCopy: copy))
            .anchorPreference(key: ReactionAnchorKey.self, value: .bounds) { (bounds: Anchor<CGRect>) -> Anchor<CGRect>? in
                isReacting ? bounds : nil
            }
            .opacity(sending ? 0.55 : 1)
            .animation(Anim.fade, value: sending)
            .frame(maxWidth: maxWidth, alignment: message.isMine ? .trailing : .leading)
    }

    /// Yours on the chip colour; others' on the card colour with a hairline, like every card. Fill and
    /// hairline follow the one outline, tail and all.
    @ViewBuilder
    private func fill(_ shape: BubbleShape) -> some View {
        if message.isMine {
            shape.fill(Ink.chip)
        } else {
            shape
                .fill(Ink.card)
                .overlay(shape.strokeBorder(Ink.hairline, lineWidth: 1))
        }
    }

    private func copy() {
        UIPasteboard.general.string = message.post.text
    }
}

/// A message bubble: a rounded body, and on the last bubble of a run a tail that sweeps out of its bottom
/// corner on the sender's side. Every bubble keeps a strip `tailWidth` wide on that side, so the bodies of
/// a run line up whether they have the tail or not. Corners are circular, so the tail's curve meets them
/// smoothly; insettable, so others' bubbles draw their hairline with `strokeBorder` on the fill's outline.
struct BubbleShape: InsettableShape {
    /// The tail's side: trailing for yours, leading for others'.
    let side: HorizontalEdge
    let hasTail: Bool
    private let inset: CGFloat

    static let tailWidth: CGFloat = 6

    init(side: HorizontalEdge, hasTail: Bool) {
        self.init(side: side, hasTail: hasTail, inset: 0)
    }

    private init(side: HorizontalEdge, hasTail: Bool, inset: CGFloat) {
        self.side = side
        self.hasTail = hasTail
        self.inset = inset
    }

    func inset(by amount: CGFloat) -> BubbleShape {
        return BubbleShape(side: side, hasTail: hasTail, inset: inset + amount)
    }

    /// Drawn with the tail on the trailing side, then mirrored for a leading one.
    func path(in rect: CGRect) -> Path {
        let frame: CGRect = rect.insetBy(dx: inset, dy: inset)
        guard frame.width > BubbleShape.tailWidth, frame.height > 0 else { return Path() }
        let outline: Path = trailingOutline(width: frame.width, height: frame.height)
        var transform: CGAffineTransform = CGAffineTransform(translationX: frame.minX, y: frame.minY)
        if side == .leading {
            transform = transform.translatedBy(x: frame.width, y: 0).scaledBy(x: -1, y: 1)
        }
        return outline.applying(transform)
    }

    /// Clockwise from the top-left corner, in (0, 0, w, h). The body ends `tailWidth` short of the trailing
    /// edge; the tail runs down the body's edge to where its corner would start, then sweeps out to a tip at
    /// the bottom-trailing corner, and the bottom edge runs straight back from the tip.
    private func trailingOutline(width w: CGFloat, height h: CGFloat) -> Path {
        let t: CGFloat = BubbleShape.tailWidth
        let x: CGFloat = w - t
        let r: CGFloat = max(0, min(Corner.bubble - inset, x / 2, h / 2))
        var path: Path = Path()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: x - r, y: 0))
        path.addArc(tangent1End: CGPoint(x: x, y: 0), tangent2End: CGPoint(x: x, y: r), radius: r)
        if hasTail {
            let start: CGFloat = h - min(r, h - r)
            let tip: CGPoint = CGPoint(x: w, y: h)
            path.addLine(to: CGPoint(x: x, y: start))
            path.addCurve(to: tip,
                          control1: CGPoint(x: x, y: start + (h - start) * 0.55),
                          control2: CGPoint(x: x + t * 0.35, y: h - t * 0.25))
        } else {
            path.addLine(to: CGPoint(x: x, y: h - r))
            path.addArc(tangent1End: CGPoint(x: x, y: h), tangent2End: CGPoint(x: x - r, y: h), radius: r)
        }
        path.addLine(to: CGPoint(x: r, y: h))
        path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - r), radius: r)
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(tangent1End: CGPoint.zero, tangent2End: CGPoint(x: r, y: 0), radius: r)
        path.closeSubpath()
        return path
    }
}

/// How a bubble answers a long press. A member's sent message opens the reaction picker after a short hold;
/// the hold gives way to a scroll or a swipe as soon as the finger moves. The empty tap ahead of it is the
/// known guard for a long press inside a scroll view, which can otherwise keep a drag that starts on the
/// bubble from scrolling; a tap on a bubble does nothing anyway. Anything else keeps the context menu with
/// Copy.
private struct BubblePress: ViewModifier {
    let canReact: Bool
    let shape: BubbleShape
    let onHold: () -> Void
    let onCopy: () -> Void

    /// Shorter than the context menu's, as in Messages.
    private static let holdSeconds: Double = 0.3

    func body(content: Content) -> some View {
        if canReact {
            content
                .contentShape(shape)
                .onTapGesture {}
                .onLongPressGesture(minimumDuration: BubblePress.holdSeconds, perform: onHold)
        } else {
            content
                .contentShape(.contextMenuPreview, shape)
                .contextMenu {
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
        }
    }
}

/// A member's initial on a quiet disc: the avatar beside others' messages, and the list of who voted.
struct ChatAvatar: View {
    let initial: String
    let size: CGFloat

    init(initial: String, size: CGFloat) {
        self.initial = initial
        self.size = size
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 3 / 7, weight: .heavy, design: .rounded))
            .foregroundStyle(Ink.text2)
            .frame(width: size, height: size)
            .background(Circle().fill(Ink.avatar))
            .accessibilityHidden(true)
    }
}

/// "Not sent · Retry · Delete" under a message or a proof of yours that failed to send. Each action has a
/// 44 pt target.
struct ChatFailedRow: View {
    let onRetry: () -> Void
    let onDelete: () -> Void

    init(onRetry: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.onRetry = onRetry
        self.onDelete = onDelete
    }

    var body: some View {
        HStack(spacing: Gap.xs) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(Ink.text2)
                .accessibilityHidden(true)
            Text("Not sent")
                .foregroundStyle(Ink.text2)
            separator
            action("Retry", perform: onRetry)
            separator
            action("Delete", perform: onDelete)
        }
        .font(Fonts.footnote)
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(Ink.text3)
            .accessibilityHidden(true)
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(Fonts.footnoteSemibold)
                .foregroundStyle(Ink.text)
                .frame(minWidth: Gap.hit, minHeight: Gap.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}
