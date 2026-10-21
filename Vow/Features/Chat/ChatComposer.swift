import SwiftUI

/// The message bar under the feed: "+" (proof or an excuse) and a growing field with Send inside it, which
/// shows only once there is something to send. Return inserts a newline; only Send sends. The text is held
/// to `Records.postTextLimit` without a counter. Its "+" target starts 16 pt in, clear of the shell's edge
/// swipe. The page lifts it over the keyboard.
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

    private static let fieldMinHeight: CGFloat = 38

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
        .padding(.vertical, Gap.xs)
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

    private var field: some View {
        HStack(alignment: .bottom, spacing: 0) {
            TextField("Message", text: $draft, prompt: Text("Message").foregroundStyle(Ink.text3), axis: .vertical)
                .font(Fonts.body)
                .foregroundStyle(Ink.text)
                .tint(Ink.text)
                .lineLimit(typeSize.isAccessibilitySize ? 1...3 : 1...5)
                .focused(focus)
                .padding(.leading, Gap.m)
                .padding(.trailing, canSend ? Gap.xs : Gap.m)
                .padding(.vertical, Gap.s)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canSend {
                sendButton
                    .transition(sendTransition)
            }
        }
        .frame(minHeight: ChatComposer.fieldMinHeight)
        .background(fieldBox)
        .padding(.vertical, Gap.xs)
        .animation(Anim.standard, value: canSend)
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

    /// A 30 pt disc inset from the field's trailing and bottom edges; its target reaches 44 pt.
    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Ink.onPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Ink.primary))
                .padding(.trailing, Gap.xs)
                .padding(.bottom, Gap.xs)
                .contentShape(Rectangle().inset(by: -5))
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
