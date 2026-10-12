import SwiftUI
import Accessibility

/// Single-line field on a Palette.raised rounded rectangle with an accent focus ring.
/// `label` is the accessibility label; `placeholder` "" shows nothing. The whole field is tappable.
/// Callers attach .onSubmit, .keyboardType and .autocorrectionDisabled outside.
struct VowField: View {
    @Binding var text: String
    let label: String
    let placeholder: String
    let capitalization: TextInputAutocapitalization
    let monospaced: Bool
    let autoFocus: Bool
    let submitLabel: SubmitLabel
    @FocusState private var focused: Bool

    init(_ label: String,
         text: Binding<String>,
         placeholder: String = "",
         capitalization: TextInputAutocapitalization = .sentences,
         monospaced: Bool = false,
         autoFocus: Bool = false,
         submitLabel: SubmitLabel = .done) {
        self._text = text
        self.label = label
        self.placeholder = placeholder
        self.capitalization = capitalization
        self.monospaced = monospaced
        self.autoFocus = autoFocus
        self.submitLabel = submitLabel
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(Palette.text3)
    }

    var body: some View {
        TextField(label, text: $text, prompt: prompt)
            .font(monospaced ? Typeface.mono : Typeface.body)
            .foregroundStyle(Palette.text)
            .tint(Palette.accent)
            .textInputAutocapitalization(capitalization)
            .submitLabel(submitLabel)
            .focused($focused)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: Space.fieldHeight, alignment: .leading)
            .background(tapArea)
            .overlay(focusRing)
            .animation(Motion.fade, value: focused)
            .task { await focusIfNeeded() }
    }

    /// Fill that also catches taps in the padding around the text, so the whole field focuses it
    /// without putting a gesture over the text field itself (keeps caret placement and selection native).
    private var tapArea: some View {
        shape
            .fill(Palette.raised)
            .contentShape(shape)
            .onTapGesture { focused = true }
    }

    private var focusRing: some View {
        shape
            .strokeBorder(Palette.accent, lineWidth: 1.5)
            .opacity(focused ? 1 : 0)
            .allowsHitTesting(false)
    }

    @MainActor
    private func focusIfNeeded() async {
        guard autoFocus else { return }
        try? await Task.sleep(nanoseconds: Motion.autoFocusNanos)
        if Task.isCancelled { return }
        focused = true
    }
}

/// Label above, content, footer below. Aligns to the gutter (no horizontal insets).
struct FormField<Content: View>: View {
    let label: String?
    let footer: String?
    let content: Content

    init(_ label: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = label {
                Text(label)
                    .font(Typeface.subheadlineSemibold)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
            if let footer = footer {
                Text(footer)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Segmented stake control: a Palette.thumb capsule slides to the selected option (Motion.standard),
/// with a selection haptic. Each segment is a full-height (44pt) target.
struct StakePicker: View {
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
        .frame(minHeight: Space.hitTarget)
        .background(Capsule().fill(Palette.raised))
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// One option. The 3pt track inset lives inside the button so the inset is tappable too.
    private func segment(_ option: Int) -> some View {
        let selected: Bool = option == selection
        return Button {
            select(option)
        } label: {
            Text(GroupFormat.stake(option))
                .font(Typeface.subheadlineSemibold)
                .foregroundStyle(selected ? Palette.text : Palette.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: Space.hitTarget - 6)
                .background(thumb(selected))
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func thumb(_ selected: Bool) -> some View {
        if selected {
            Capsule()
                .fill(Palette.thumb)
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
                .matchedGeometryEffect(id: "thumb", in: thumbSpace)
        }
    }

    private func select(_ option: Int) {
        guard option != selection else { return }
        withAnimation(Motion.standard) {
            selection = option
        }
    }
}

/// Toggle on a Palette.raised rounded rectangle, accent when on.
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(Typeface.body)
                .foregroundStyle(Palette.text)
        }
        .tint(Palette.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: Space.fieldHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                .fill(Palette.raised)
        )
    }
}

/// Inline error: alert icon + message in Palette.loss, wrapping. Announced to VoiceOver when it appears.
struct ErrorText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(Typeface.footnote)
        .foregroundStyle(Palette.loss)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            AccessibilityNotification.Announcement(text).post()
        }
    }
}
