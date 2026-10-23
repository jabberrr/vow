import SwiftUI

/// The bounds of the message the reaction picker is open over, for the page to place the picker and leave
/// the bubble clear of its scrim. Only that message reports them, so the page always finds it where it is.
struct ReactionAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Where the picker sits over a held message, in the page's coordinates.
struct ReactionPlace {
    let origin: CGPoint
    /// Above the bubble; false below it, or over its top when the page has room on neither side.
    let above: Bool
}

/// What a long press on a message offers: `Reactions.choices` in a pill, then Copy, since the hold takes the
/// place of the context menu. Your current reaction is ringed and tapping it takes it back. Fixed sizes, like
/// symbols: the emoji are pictures. VoiceOver is held inside it and starts on your reaction, or the first;
/// escape closes it.
struct ReactionPicker: View {
    /// Your current reaction to the message, if any.
    let mine: String?
    /// Each target's side.
    let cell: CGFloat
    /// An emoji, or nil to take yours back.
    let onReact: (String?) -> Void
    let onCopy: () -> Void
    let onClose: () -> Void

    @AccessibilityFocusState private var focused: String?

    /// The rule before Copy, with its margins.
    private static let dividerWidth: CGFloat = 1 + 2 * Gap.xs
    private static let copyID: String = "copy"

    init(mine: String?,
         cell: CGFloat,
         onReact: @escaping (String?) -> Void,
         onCopy: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.mine = mine
        self.cell = cell
        self.onReact = onReact
        self.onCopy = onCopy
        self.onClose = onClose
    }

    // MARK: - Geometry

    /// 44 pt targets, narrower only on a page too narrow for them all (a zoomed iPhone SE).
    static func cell(forWidth width: CGFloat) -> CGFloat {
        let targets: CGFloat = CGFloat(Reactions.choices.count + 1)
        let fits: CGFloat = ((width - dividerWidth - 2 * Gap.xs) / targets).rounded(.down)
        return max(0, min(Gap.hit, fits))
    }

    static func size(cell: CGFloat) -> CGSize {
        let targets: CGFloat = CGFloat(Reactions.choices.count + 1)
        return CGSize(width: targets * cell + dividerWidth + 2 * Gap.xs, height: cell + 2 * Gap.xs)
    }

    /// Just above the bubble, or just below it when there is no room above, or over its top when there is
    /// room on neither side (a message taller than the page). Its edge lines up with the bubble's on the
    /// sender's side, kept `Gap.s` inside the page.
    static func place(_ picker: CGSize, by bubble: CGRect, alignTrailing: Bool, in page: CGSize) -> ReactionPlace {
        let margin: CGFloat = Gap.s
        let preferred: CGFloat = alignTrailing ? bubble.maxX - picker.width : bubble.minX
        let x: CGFloat = max(margin, min(preferred, page.width - margin - picker.width))
        let above: CGFloat = bubble.minY - Gap.s - picker.height
        if above >= margin {
            return ReactionPlace(origin: CGPoint(x: x, y: above), above: true)
        }
        let below: CGFloat = bubble.maxY + Gap.s
        let y: CGFloat = below + picker.height <= page.height - margin ? max(margin, below) : margin
        return ReactionPlace(origin: CGPoint(x: x, y: y), above: false)
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Reactions.choices, id: \.self) { (emoji: String) in
                choice(emoji)
            }
            Rectangle()
                .fill(Ink.hairline)
                .frame(width: 1, height: cell / 2)
                .padding(.horizontal, Gap.xs)
                .accessibilityHidden(true)
            copyButton
        }
        .padding(Gap.xs)
        .background(Capsule().fill(Ink.toast).shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .onAppear {
            focused = mine ?? Reactions.choices.first
        }
    }

    private func choice(_ emoji: String) -> some View {
        let isMine: Bool = emoji == mine
        return Button {
            onReact(isMine ? nil : emoji)
        } label: {
            Text(emoji)
                .font(.system(size: (cell * 0.6).rounded()))
                .frame(width: cell, height: cell)
                .background(ring.opacity(isMine ? 1 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(emoji)
        .accessibilityHint(isMine ? "Takes back your reaction" : "")
        .accessibilityAddTraits(isMine ? .isSelected : [])
        .accessibilityFocused($focused, equals: emoji)
    }

    /// Your reaction's mark: the chip colour, outlined like your own chip under a message.
    private var ring: some View {
        Circle()
            .fill(Ink.chip)
            .overlay(Circle().strokeBorder(Ink.text, lineWidth: 1.5))
            .padding(Gap.xxs)
    }

    private var copyButton: some View {
        Button(action: onCopy) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ink.text)
                .frame(width: cell, height: cell)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Copy")
        .accessibilityFocused($focused, equals: ReactionPicker.copyID)
    }
}

/// The reactions under a message: one chip per emoji with how many chose it, yours outlined. A member's tap
/// on a chip toggles their reaction to that emoji; anyone else only sees them. A chip's target reaches
/// `Gap.s` above and below it but never sideways, where its neighbour is only `Gap.xs` away. VoiceOver
/// doesn't visit them: the message is one element, whose value lists them and whose actions react. Their
/// text stops growing at xxLarge, so the large content viewer shows each one.
struct ReactionChips: View {
    let reactions: [ReactionCount]
    /// A member, and the message is sent.
    let canReact: Bool
    /// An emoji, or nil to take yours back.
    let onReact: (String?) -> Void

    init(reactions: [ReactionCount], canReact: Bool, onReact: @escaping (String?) -> Void) {
        self.reactions = reactions
        self.canReact = canReact
        self.onReact = onReact
    }

    var body: some View {
        HStack(spacing: Gap.xs) {
            ForEach(reactions, id: \.emoji) { (reaction: ReactionCount) in
                chip(reaction)
                    .accessibilityShowsLargeContentViewer {
                        Text(reaction.emoji + " " + String(reaction.count))
                    }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// The padding that widens the target is taken back from the layout, so the chips keep their size.
    @ViewBuilder
    private func chip(_ reaction: ReactionCount) -> some View {
        if canReact {
            Button {
                onReact(reaction.mine ? nil : reaction.emoji)
            } label: {
                face(reaction)
                    .padding(.vertical, Gap.s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .padding(.vertical, -Gap.s)
        } else {
            face(reaction)
        }
    }

    private func face(_ reaction: ReactionCount) -> some View {
        HStack(spacing: Gap.xs) {
            Text(reaction.emoji)
                .font(Fonts.footnote)
            Text("\(reaction.count)")
                .font(Fonts.captionBold)
                .monospacedDigit()
                .foregroundStyle(reaction.mine ? Ink.text : Ink.text2)
        }
        .padding(.horizontal, Gap.s)
        .padding(.vertical, Gap.xs)
        .background(chipFace(mine: reaction.mine))
    }

    /// Yours on the chip colour with an outline; others' on the field colour.
    @ViewBuilder
    private func chipFace(mine: Bool) -> some View {
        if mine {
            Capsule()
                .fill(Ink.chip)
                .overlay(Capsule().strokeBorder(Ink.text, lineWidth: 1.5))
        } else {
            Capsule()
                .fill(Ink.field)
        }
    }
}

/// The reaction picker's scrim: the whole page, with the held bubble cut out (even-odd fill) so it stays lit.
struct ScrimCutout: Shape {
    /// The bubble's bounds in the scrim's space.
    let hole: CGRect
    let bubble: BubbleShape

    init(hole: CGRect, bubble: BubbleShape) {
        self.hole = hole
        self.bubble = bubble
    }

    func path(in rect: CGRect) -> Path {
        var path: Path = Path(rect)
        path.addPath(bubble.path(in: hole))
        return path
    }
}
