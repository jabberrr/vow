import SwiftUI
import UIKit

/// One text message. Others' runs lead with a name line and end with a letter disc (a disc, not a Sphere:
/// a Sphere's light means "kept today"); yours sit on the trailing side under their time. A message that is
/// sending is faded; one that failed stays at full strength with "Not sent · Retry · Delete" under it.
struct MessageBubble: View {
    let message: ChatMessage
    /// The message's time in the group's time zone: "8:21 PM".
    let time: String
    let failed: Bool
    /// 72 % of the page's width.
    let maxWidth: CGFloat
    let onRetry: () -> Void
    let onDelete: () -> Void

    private static let avatarSize: CGFloat = 28

    init(message: ChatMessage,
         time: String,
         failed: Bool,
         maxWidth: CGFloat,
         onRetry: @escaping () -> Void,
         onDelete: @escaping () -> Void) {
        self.message = message
        self.time = time
        self.failed = failed
        self.maxWidth = maxWidth
        self.onRetry = onRetry
        self.onDelete = onDelete
    }

    private var sending: Bool {
        message.post.serverDate == nil && !failed
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Corner.bubble, style: .continuous)
    }

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((message.isMine ? "You" : message.author) + ", " + message.post.text)
            .accessibilityValue(ChatText.messageValue(time: time, sending: sending, failed: failed))
            .accessibilityActions {
                Button("Copy", action: copy)
                if failed {
                    Button("Retry", action: onRetry)
                    Button("Delete", action: onDelete)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if message.isMine {
            mine
        } else {
            theirs
        }
    }

    // MARK: - Runs

    private var mine: some View {
        VStack(alignment: .trailing, spacing: Gap.xs) {
            if message.startsRun {
                Text(time)
                    .font(Fonts.footnote)
                    .foregroundStyle(Ink.text3)
            }
            bubble
            if failed {
                ChatFailedRow(onRetry: onRetry, onDelete: onDelete)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var theirs: some View {
        VStack(alignment: .leading, spacing: Gap.xs) {
            if message.startsRun {
                nameLine
                    .padding(.leading, MessageBubble.avatarSize + Gap.s)
            }
            HStack(alignment: .bottom, spacing: Gap.s) {
                if message.endsRun {
                    ChatAvatar(initial: message.initial, size: MessageBubble.avatarSize)
                } else {
                    Color.clear
                        .frame(width: MessageBubble.avatarSize, height: 0)
                }
                bubble
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

    // MARK: - Bubble

    private var bubble: some View {
        Text(message.post.text)
            .font(Fonts.body)
            .foregroundStyle(Ink.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Gap.m)
            .padding(.vertical, Gap.s)
            .background(fill)
            .contentShape(.contextMenuPreview, shape)
            .contextMenu {
                Button(action: copy) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            .opacity(sending ? 0.55 : 1)
            .animation(Anim.fade, value: sending)
            .frame(maxWidth: maxWidth, alignment: message.isMine ? .trailing : .leading)
    }

    /// Yours on the chip colour; others' on the card colour with a hairline, like every card.
    @ViewBuilder
    private var fill: some View {
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
