import SwiftUI
import UIKit

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
        SheetChrome(title: "Join a group") {
            Text("Paste the invite link a friend shared with you. Opening the link on this iPhone works too.")
                .font(Theme.display(15, .regular))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            FieldSection("Invite link") {
                GlassField(
                    placeholder: "https://www.icloud.com/share/…",
                    text: $link,
                    font: Theme.mono(14, .medium),
                    capitalization: .never
                )
                .keyboardType(.URL)
                .autocorrectionDisabled(true)
            }
            if let text = errorText {
                Text(text)
                    .font(Theme.mono(12, .medium))
                    .foregroundStyle(Theme.pink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(title: "Join", busy: busy, enabled: url != nil, action: join)
        }
        .onAppear(perform: prefill)
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
                errorText = "Couldn't join with that link. Check it and try again."
            }
        }
    }
}
