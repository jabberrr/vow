import SwiftUI

struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Fonts.footnoteSemibold)
            .foregroundStyle(Ink.text2)
            .padding(.horizontal, Gap.xs)
            .padding(.bottom, Gap.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

struct FieldFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Fonts.footnote)
            .foregroundStyle(Ink.text3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Gap.xs)
            .padding(.top, Gap.s)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FormError: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Fonts.footnote)
            .foregroundStyle(Ink.loss)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Gap.xs)
            .padding(.top, Gap.m)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The field-shaped box for custom content (a TextField plus an accessory, or a read-only link).
struct FieldBox<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: Gap.control, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Corner.field, style: .continuous).fill(Ink.field))
    }
}

/// Text field on the field box. Single line by default (callers attach .onSubmit). `multiline` wraps up
/// to 4 lines (for vows); Return then never inserts a newline and calls `onReturn` instead.
struct VowTextField: View {
    @Binding var text: String
    let label: String
    let placeholder: String
    let capitalization: TextInputAutocapitalization
    let monospaced: Bool
    let autoFocus: Bool
    let submitLabel: SubmitLabel
    let multiline: Bool
    let onReturn: () -> Void
    @FocusState private var focused: Bool

    init(_ label: String,
         text: Binding<String>,
         placeholder: String = "",
         capitalization: TextInputAutocapitalization = .sentences,
         monospaced: Bool = false,
         autoFocus: Bool = false,
         submitLabel: SubmitLabel = .done,
         multiline: Bool = false,
         onReturn: @escaping () -> Void = {}) {
        self._text = text
        self.label = label
        self.placeholder = placeholder
        self.capitalization = capitalization
        self.monospaced = monospaced
        self.autoFocus = autoFocus
        self.submitLabel = submitLabel
        self.multiline = multiline
        self.onReturn = onReturn
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Corner.field, style: .continuous)
    }

    var body: some View {
        field
            .font(monospaced ? Fonts.mono : Fonts.body)
            .foregroundStyle(Ink.text)
            .tint(Ink.text)
            .textInputAutocapitalization(capitalization)
            .submitLabel(submitLabel)
            .focused($focused)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: Gap.control, alignment: .leading)
            .background(tapArea)
            .overlay(focusRing)
            .animation(Anim.fade, value: focused)
            .onChange(of: text) { _, newValue in
                handleNewline(newValue)
            }
            .task {
                await focusIfNeeded()
            }
    }

    @ViewBuilder
    private var field: some View {
        if multiline {
            TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Ink.text3), axis: .vertical)
                .lineLimit(1...4)
        } else {
            TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Ink.text3))
        }
    }

    /// Multiline only: Return arrives as "\n"; strip it and treat it as submit.
    private func handleNewline(_ value: String) {
        guard multiline, value.contains("\n") else { return }
        text = value.replacingOccurrences(of: "\n", with: "")
        onReturn()
    }

    /// Catches taps in the padding so the whole box focuses the field.
    private var tapArea: some View {
        shape
            .fill(Ink.field)
            .contentShape(shape)
            .onTapGesture {
                focused = true
            }
    }

    private var focusRing: some View {
        shape
            .strokeBorder(Ink.text.opacity(0.35), lineWidth: 1.5)
            .opacity(focused ? 1 : 0)
            .allowsHitTesting(false)
    }

    @MainActor
    private func focusIfNeeded() async {
        guard autoFocus else { return }
        try? await Task.sleep(nanoseconds: Anim.focusNanos)
        if Task.isCancelled { return }
        focused = true
    }
}

/// 1 / 2 / 5 / 10 segmented selector.
struct StakeSelector: View {
    @Binding var selection: Int
    let options: [Int]
    @Namespace private var thumbSpace

    init(selection: Binding<Int>, options: [Int] = Points.stakeOptions) {
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(3)
        .frame(minHeight: Gap.control)
        .background(RoundedRectangle(cornerRadius: Corner.field, style: .continuous).fill(Ink.field))
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func segment(_ option: Int) -> some View {
        let selected: Bool = option == selection
        return Button {
            select(option)
        } label: {
            Text("\(option)")
                .font(Fonts.numberMedium)
                .foregroundStyle(selected ? Ink.onPrimary : Ink.text2)
                .frame(maxWidth: .infinity, minHeight: Gap.control - 6)
                .background(thumb(selected))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option == 1 ? "1 point" : "\(option) points")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func thumb(_ selected: Bool) -> some View {
        if selected {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Ink.primary)
                .matchedGeometryEffect(id: "thumb", in: thumbSpace)
        }
    }

    private func select(_ option: Int) {
        guard option != selection else { return }
        withAnimation(Anim.standard) {
            selection = option
        }
    }
}

/// Rows container (field fill, 14 radius).
struct FormGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(RoundedRectangle(cornerRadius: Corner.field, style: .continuous).fill(Ink.field))
        .clipShape(RoundedRectangle(cornerRadius: Corner.field, style: .continuous))
    }
}

struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(Fonts.body)
                .foregroundStyle(Ink.text)
        }
        .tint(Ink.gain)
        .padding(.horizontal, 16)
        .frame(minHeight: Gap.control)
    }
}

struct ValueRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: Gap.s) {
            Text(title)
                .foregroundStyle(Ink.text)
            Spacer(minLength: Gap.s)
            Text(value)
                .foregroundStyle(Ink.text2)
                .monospacedDigit()
        }
        .font(Fonts.body)
        .padding(.horizontal, 16)
        .frame(minHeight: Gap.control)
        .accessibilityElement(children: .combine)
    }
}
