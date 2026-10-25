import SwiftUI

/// The message bar under the feed: "+" (proof or an excuse) and a growing field with Send inside it, which
/// shows only once there is something to send. Return inserts a newline; only Send sends. The text is held
/// to `Records.postTextLimit` without a counter. Its "+" target starts 16 pt in, clear of the shell's edge
/// swipe. The page owns the focus and lifts the bar over the keyboard.
struct ChatComposer: View {
    @Binding var draft: String
    let focus: FocusState<Bool>.Binding
    /// The "+" card is open: the disc shows a close mark.
    let plusOpen: Bool
    let onPlus: () -> Void
    /// The text to send; the field is already cleared.
    let onSend: (String) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize: DynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    /// How much further in the typed text starts than "Message" does. The caret stands at the text's very start,
    /// while a letter's ink begins a little after its own (its side bearing), so with both at one inset the caret
    /// sat just left of the "M". About a caret's width at the default size, it grows with the text.
    @ScaledMetric(relativeTo: .body) private var caretInset: CGFloat = Gap.xxs

    /// A single line's height: the "+" target's, so the two sit level.
    private static let fieldMinHeight: CGFloat = Gap.hit

    init(draft: Binding<String>,
         focus: FocusState<Bool>.Binding,
         plusOpen: Bool,
         onPlus: @escaping () -> Void,
         onSend: @escaping (String) -> Void) {
        self._draft = draft
        self.focus = focus
        self.plusOpen = plusOpen
        self.onPlus = onPlus
        self.onSend = onSend
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Gap.xs) {
            plusButton
            field
        }
        .padding(.leading, Gap.l)
        .padding(.trailing, Gap.m)
        .padding(.vertical, Gap.s)
        .background(Ink.bg)
        .onChange(of: draft) { (_: String, text: String) in
            clamp(text)
        }
    }

    // MARK: - Plus

    /// A 36 pt disc in a 44 pt target; open, it turns to the chip colour with a close mark (a crossfade,
    /// no rotation).
    private var plusButton: some View {
        Button(action: onPlus) {
            ZStack {
                Circle()
                    .fill(plusOpen ? Ink.chip : Ink.field)
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .opacity(plusOpen ? 0 : 1)
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .opacity(plusOpen ? 1 : 0)
            }
            .foregroundStyle(Ink.text)
            .frame(width: 36, height: 36)
            .frame(width: Gap.hit, height: Gap.hit)
            .contentShape(Rectangle())
            .animation(Anim.press, value: plusOpen)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Add")
        .accessibilityHint("Proof or an excuse")
    }

    // MARK: - Field

    /// The text is centred in a box at least as tall as the "+" target, starting `caretInset` further in than
    /// "Message", so the caret stands on the placeholder's first letter; the field draws no prompt of its own
    /// (`placeholder`).
    private var field: some View {
        HStack(alignment: .bottom, spacing: 0) {
            TextField("", text: $draft, axis: .vertical)
                .font(Fonts.body)
                .foregroundStyle(Ink.text)
                .tint(Ink.text)
                .lineLimit(typeSize.isAccessibilitySize ? 1...3 : 1...5)
                .focused(focus)
                .accessibilityLabel("Message")
                .padding(.leading, Gap.m + caretInset)
                .padding(.trailing, canSend ? Gap.xs : Gap.m)
                .padding(.vertical, Gap.s)
                .frame(maxWidth: .infinity, minHeight: ChatComposer.fieldMinHeight, alignment: .leading)
                .background(alignment: .leading) {
                    placeholder
                }
            if canSend {
                sendButton
                    .transition(sendTransition)
            }
        }
        .background(fieldBox)
        .animation(Anim.standard, value: canSend)
    }

    /// "Message" until you type, the field focused or not, as in Messages. It is centred in the box, where a
    /// single line of the field is too: a vertical field draws its own prompt at the top of its text view, whose
    /// reported height needn't be its line's (iOS 26 changes it on first focus), so that prompt sat high in the
    /// box. Text being composed (a Japanese keyboard's, say) is already in the draft, so it hides the placeholder
    /// too. It goes and comes back at once, never with Send's animation, so it never fades over the first letter
    /// typed, while moving with the bar as it rides the keyboard. It lies behind the field, so the caret is drawn
    /// over it, takes no touches, and VoiceOver hears the field's label instead.
    private var placeholder: some View {
        Text("Message")
            .font(Fonts.body)
            .foregroundStyle(Ink.text3)
            .lineLimit(1)
            .padding(.horizontal, Gap.m)
            .opacity(draft.isEmpty ? 1 : 0)
            .animation(nil, value: draft.isEmpty)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Catches taps in the field's padding, so the whole box focuses it.
    private var fieldBox: some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: Corner.bubble, style: .continuous)
        return shape
            .fill(Ink.field)
            .contentShape(shape)
            .onTapGesture {
                focus.wrappedValue = true
            }
    }

    /// Send grows in from 0.8 as it fades in; under Reduce Motion it only fades.
    private var sendTransition: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .scale(scale: 0.8))
    }

    /// A 34 pt disc centred in a 44 pt target in the field's trailing bottom corner, so it sits level with a
    /// single line and stays by the last as the field grows.
    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Ink.onPrimary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Ink.primary))
                .frame(width: Gap.hit, height: Gap.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Send")
    }

    private func send() {
        let text: String = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        onSend(text)
    }

    /// Pasted or dictated text past the limit is cut, so Send never meets a message the store would refuse.
    private func clamp(_ text: String) {
        guard text.count > Records.postTextLimit else { return }
        draft = String(text.prefix(Records.postTextLimit))
    }
}
