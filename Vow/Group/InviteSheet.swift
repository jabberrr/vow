import SwiftUI
import UIKit

/// Share or copy a group's invite link. Shows a preparing state (with Refresh) until the link exists.
struct InviteSheet: View {
    let id: GroupID

    @Environment(AppStore.self) private var store
    @State private var copied: Bool = false
    @State private var refreshing: Bool = false

    private var group: GroupInfo? {
        store.snapshots[id]?.group
    }

    private var name: String {
        group?.name ?? "your group"
    }

    private var stakeText: String {
        GroupFormat.stake(group?.stake ?? 0)
    }

    private var shareMessage: String {
        "Join \(name) on Vow. \(stakeText) a day."
    }

    var body: some View {
        SheetChrome(title: "Invite to \(name)", subtitle: "Anyone with the link can join.") {
            linkSection
        }
        .presentationDetents([.medium, .large])
        .task(id: id) {
            if group?.shareURL == nil {
                await store.refresh(id)
            }
        }
    }

    /// Ready or preparing; the two cross-fade in place when the link arrives.
    private var linkSection: some View {
        ZStack(alignment: .top) {
            if let url = group?.shareURL {
                ready(url)
            } else {
                preparing
            }
        }
        .animation(Motion.fade, value: group?.shareURL)
    }

    private func ready(_ url: URL) -> some View {
        VStack(spacing: 12) {
            linkBox {
                linkIcon
                Text(url.absoluteString)
                    .font(Typeface.mono)
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .textSelection(.enabled)
            shareButton(url)
                .padding(.top, 12)
            SecondaryButton(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc", action: copyLink)
                .sensoryFeedback(.success, trigger: copied)
        }
    }

    private var preparing: some View {
        VStack(spacing: 12) {
            linkBox {
                ProgressView()
                    .controlSize(.small)
                    .tint(Palette.text3)
                Text("Preparing link…")
                    .font(Typeface.subheadline)
                    .foregroundStyle(Palette.text3)
            }
            // Disabled stand-in for the share button, so VoiceOver reads it as a dimmed button.
            PrimaryButton("Share link", systemImage: "square.and.arrow.up", enabled: false, action: {})
                .padding(.top, 12)
            SecondaryButton(refreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise", enabled: !refreshing, action: refresh)
        }
    }

    private func shareButton(_ url: URL) -> some View {
        ShareLink(item: url, subject: Text("Join my group on Vow"), message: Text(shareMessage)) {
            PrimaryLabel(title: "Share link", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(PressableStyle())
    }

    private var linkIcon: some View {
        Image(systemName: "link")
            .font(Typeface.subheadline)
            .foregroundStyle(Palette.text2)
            .accessibilityHidden(true)
    }

    /// Raised field-shaped box the link (or the preparing line) sits in.
    private func linkBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: Space.fieldHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                .fill(Palette.raised)
        )
    }

    private func copyLink() {
        guard let url = group?.shareURL else { return }
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
