import SwiftUI
import UIKit

/// Share or copy a group's invite link. Shows a preparing state (with Refresh) until the link exists.
struct InviteLinkSheet: View {
    let id: GroupID

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var copied: Bool = false
    @State private var refreshing: Bool = false

    init(id: GroupID) {
        self.id = id
    }

    private var group: GroupInfo? {
        store.snapshots[id]?.group
    }

    private var shareURL: URL? {
        group?.shareURL
    }

    private var name: String {
        group?.name ?? "your group"
    }

    private var shareMessage: String {
        "Join \(name) on Vow. \(StakeText.perDay(group?.stake ?? 0))."
    }

    var body: some View {
        SheetScaffold(title: "Invite to \(name)", subtitle: "Anyone with the link can join.", onClose: { dismiss() }) {
            linkSection
        } footer: {
            shareSection
                .animation(Anim.fade, value: shareURL)
        }
        .sensoryFeedback(.success, trigger: copied)
        .task(id: id) {
            if group?.shareURL == nil {
                await store.refresh(id)
            }
        }
    }

    /// Ready or preparing; the two crossfade in place when the link arrives.
    private var linkSection: some View {
        ZStack(alignment: .top) {
            if let url = shareURL {
                ready(url)
                    .transition(.opacity)
            } else {
                preparing
                    .transition(.opacity)
            }
        }
        .animation(Anim.fade, value: shareURL)
    }

    private func ready(_ url: URL) -> some View {
        FieldBox {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.text2)
                .accessibilityHidden(true)
            Text(url.absoluteString)
                .font(Fonts.mono)
                .foregroundStyle(Ink.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            FieldAccessoryButton(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", action: copyLink)
        }
    }

    private var preparing: some View {
        FieldBox {
            ProgressView()
                .controlSize(.small)
                .tint(Ink.text3)
            Text("Preparing link…")
                .font(Fonts.subheadline)
                .foregroundStyle(Ink.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
            FieldAccessoryButton(refreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise", enabled: !refreshing, action: refresh)
        }
    }

    @ViewBuilder
    private var shareSection: some View {
        if let url = shareURL {
            ShareLink(item: url, subject: Text("Join my group on Vow"), message: Text(shareMessage)) {
                PillLabel("Share link", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PressStyle())
            .transition(.opacity)
        } else {
            // Disabled stand-in, so VoiceOver reads it as a dimmed button.
            PillButton("Share link", systemImage: "square.and.arrow.up", enabled: false, action: {})
                .transition(.opacity)
        }
    }

    private func copyLink() {
        guard let url = shareURL else { return }
        UIPasteboard.general.string = url.absoluteString
        copied = true
    }

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task { @MainActor in
            await store.refresh(id)
            refreshing = false
        }
    }
}
