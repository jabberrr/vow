import SwiftUI

struct GroupView: View {
    let id: GroupID

    @Environment(AppStore.self) private var store
    @State private var showVowPrompt: Bool = false
    @State private var showInvite: Bool = false
    @State private var confirmLeave: Bool = false
    @State private var confirmDelete: Bool = false

    private var groupName: String {
        store.snapshots[id]?.group.name ?? "this group"
    }

    private var isOwner: Bool {
        store.isOwner(id)
    }

    private var isActiveMember: Bool {
        guard let member = store.myMember(id) else { return false }
        return member.leftDay == nil
    }

    private var showsTestBar: Bool {
        guard let group = store.snapshots[id]?.group else { return false }
        return store.testingMode && group.isTest && isOwner
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            content
        }
        .safeAreaInset(edge: .bottom) {
            if showsTestBar {
                TestBar(id: id)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                inviteButton
                menu
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showVowPrompt) {
            VowPromptSheet(id: id)
                .environment(store)
        }
        .sheet(isPresented: $showInvite) {
            InviteSheet(id: id)
                .environment(store)
        }
        .confirmationDialog("Leave \(groupName)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave group", role: .destructive) {
                Task { await store.leave(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You stop staking from today. Your past days stay in the group's ledger.")
        }
        .confirmationDialog("Delete \(groupName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete group", role: .destructive) {
                Task { await store.deleteGroup(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the group and its history for every member. It can't be undone.")
        }
        .task(id: id) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                await store.refresh(id)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = store.snapshots[id], let summary = store.summary(for: id) {
            ScrollView(.vertical, showsIndicators: false) {
                GroupColumn(
                    group: snapshot.group,
                    summary: summary,
                    theme: store.theme(for: id),
                    viewerID: store.userID ?? "",
                    since: GroupFormat.since(member: store.myMember(id), group: snapshot.group),
                    onSealed: { Task { await store.checkIn(id) } },
                    onSetVow: { showVowPrompt = true }
                )
            }
            .refreshable {
                await store.refresh(id)
            }
        } else {
            ProgressView()
                .tint(Color.white.opacity(0.7))
        }
    }

    private var inviteButton: some View {
        Button {
            showInvite = true
        } label: {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .accessibilityLabel("Invite")
    }

    private var menu: some View {
        Menu {
            Button {
                showVowPrompt = true
            } label: {
                Label(isActiveMember ? "Edit my vow" : "Set my vow", systemImage: "pencil")
            }
            Button {
                Task { await store.refresh(id) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Divider()
            destructiveItem
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
        }
    }

    @ViewBuilder
    private var destructiveItem: some View {
        if isOwner {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete group", systemImage: "trash")
            }
        } else {
            Button(role: .destructive) {
                confirmLeave = true
            } label: {
                Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }
}
