import SwiftUI
import UIKit

struct InviteSheet: View {
    let id: GroupID

    @Environment(AppStore.self) private var store
    @State private var copied: Bool = false
    @State private var refreshing: Bool = false

    private var group: GroupInfo? {
        store.snapshots[id]?.group
    }

    private var name: String {
        group?.name ?? "my group"
    }

    private var stakeText: String {
        GroupFormat.stake(group?.stake ?? 0)
    }

    var body: some View {
        SheetChrome(title: "Invite friends") {
            Text("Anyone with this link can join \(name). They swear their own vow and stake \(stakeText) a day.")
                .font(Theme.display(15, .regular))
                .foregroundStyle(Color.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            if let url = group?.shareURL {
                ready(url)
            } else {
                preparing
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: id) {
            if group?.shareURL == nil {
                await store.refresh(id)
            }
        }
    }

    private func ready(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(url.absoluteString)
                .font(Theme.mono(12, .medium))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(padding: 14, radius: 16)
            ShareLink(
                item: url,
                subject: Text("Join my Vow group"),
                message: Text(shareMessage)
            ) {
                PrimaryLabel(title: "Share invite")
            }
            .buttonStyle(.plain)
            SecondaryButton(title: copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = url.absoluteString
                copied = true
            }
        }
    }

    private var shareMessage: String {
        "Join \"\(name)\" on Vow — stake \(stakeText) a day."
    }

    private var preparing: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrimaryLabel(title: "Preparing invite link…")
                .opacity(0.4)
            SecondaryButton(title: refreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise") {
                refresh()
            }
            .disabled(refreshing)
        }
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
