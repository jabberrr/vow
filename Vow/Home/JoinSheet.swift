import SwiftUI
import UIKit

/// Join a group from a pasted invite link. Prefills an iCloud share link from the pasteboard.
struct JoinSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var link: String = ""
    @State private var busy: Bool = false
    @State private var errorText: String?

    private var url: URL? {
        let trimmed: String = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = URL(string: trimmed), parsed.scheme != nil else {
            return nil
        }
        return parsed
    }

    var body: some View {
        SheetChrome(title: "Join a group", subtitle: "Paste an invite link, or open it on this iPhone.") {
            linkField
            if let message = errorText {
                ErrorText(message)
            }
            PrimaryButton("Join", busy: busy, enabled: url != nil, action: join)
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: prefill)
    }

    private var linkField: some View {
        VowField("Invite link", text: $link, placeholder: "Invite link", capitalization: .never, monospaced: true)
            .keyboardType(.URL)
            .autocorrectionDisabled(true)
    }

    private func prefill() {
        guard link.isEmpty, UIPasteboard.general.hasStrings else { return }
        if let text = UIPasteboard.general.string, text.contains("icloud.com/share") {
            link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
