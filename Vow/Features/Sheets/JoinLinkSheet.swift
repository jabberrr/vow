import SwiftUI
import UIKit

/// Dismisses itself on success (the store then raises pendingVowPrompt or bumps acceptCount).
/// Paste goes through the system PasteButton, so there is no paste-permission alert.
struct JoinLinkSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var link: String = ""
    @State private var busy: Bool = false
    @State private var errorText: String? = nil
    @FocusState private var focused: Bool

    init() {}

    private var url: URL? {
        let trimmed: String = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = URL(string: trimmed), parsed.scheme != nil else {
            return nil
        }
        return parsed
    }

    var body: some View {
        SheetScaffold(title: "Join a group", onClose: { dismiss() }) {
            form
        } footer: {
            PillButton("Join", busy: busy, enabled: url != nil, action: join)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            linkBox
            FieldFooter("Opening the link on this iPhone works too.")
            if let message = errorText {
                FormError(message)
            }
        }
    }

    private var linkBox: some View {
        FieldBox {
            linkField
            if link.isEmpty {
                pasteButton
            }
        }
        .overlay(focusRing)
        .animation(Anim.fade, value: focused)
    }

    private var linkField: some View {
        TextField("Invite link", text: $link, prompt: Text("Invite link").foregroundStyle(Ink.text3))
            .font(Fonts.mono)
            .foregroundStyle(Ink.text)
            .tint(Ink.text)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.join)
            .onSubmit(join)
            .focused($focused)
            .frame(maxWidth: .infinity, minHeight: Gap.control, alignment: .leading)
            .background(tapArea)
    }

    private var pasteButton: some View {
        PasteButton(payloadType: String.self) { strings in
            Task { @MainActor in
                link = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? link
            }
        }
        .buttonBorderShape(.capsule)
        .tint(Ink.chip)
        .labelStyle(.titleAndIcon)
    }

    /// Catches taps around the text so the whole box focuses the field.
    private var tapArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                focused = true
            }
    }

    private var focusRing: some View {
        RoundedRectangle(cornerRadius: Corner.field, style: .continuous)
            .strokeBorder(Ink.text.opacity(0.35), lineWidth: 1.5)
            .opacity(focused ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func join() {
        guard let target = url, !busy else { return }
        busy = true
        errorText = nil
        Task { @MainActor in
            let ok: Bool = await store.join(url: target)
            busy = false
            if ok {
                dismiss()
            } else {
                errorText = "Couldn't join with that link. " + (store.lastError ?? "Check it and try again.")
            }
        }
    }
}
