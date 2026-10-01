import SwiftUI

/// Identifiable wrapper so a GroupID can drive `.sheet(item:)`.
struct GroupSheetTarget: Identifiable, Equatable {
    let id: GroupID
}

/// Owns the navigation stack and every Home-level sheet (create, join, invite, vow prompt).
struct HomeView: View {
    @Environment(AppStore.self) private var store

    @State private var path: [GroupID] = []
    @State private var showCreate: Bool = false
    @State private var showJoin: Bool = false
    @State private var invite: GroupSheetTarget?
    @State private var createdID: GroupID?
    /// True from opening a Home sheet until its onDismiss, so the vow prompt never collides with it.
    @State private var modalOpen: Bool = false
    @State private var openAfterPrompt: GroupID?
    @State private var openAfterInvite: GroupID?

    var body: some View {
        let promptTarget: GroupSheetTarget? = modalOpen ? nil : store.pendingVowPrompt.map { GroupSheetTarget(id: $0) }
        NavigationStack(path: $path) {
            HomeScreen(onCreate: openCreate, onJoin: openJoin)
                .navigationDestination(for: GroupID.self) { groupID in
                    GroupView(id: groupID)
                }
        }
        .sheet(isPresented: $showCreate, onDismiss: createDismissed) {
            CreateGroupSheet(onCreated: { newID in createdID = newID })
                .environment(store)
        }
        .sheet(isPresented: $showJoin, onDismiss: { modalOpen = false }) {
            JoinSheet()
                .environment(store)
        }
        .sheet(item: $invite, onDismiss: inviteDismissed) { target in
            InviteSheet(id: target.id)
                .environment(store)
        }
        .sheet(item: promptBinding(promptTarget), onDismiss: promptDismissed) { target in
            VowPromptSheet(id: target.id)
                .environment(store)
        }
        .onChange(of: store.groupIDs) { _, ids in
            path.removeAll { !ids.contains($0) }
        }
        .onChange(of: store.pendingVowPrompt) { oldValue, newValue in
            // Swearing (store clears it) or swiping the prompt away: open that group afterwards.
            if let finished = oldValue, newValue == nil {
                openAfterPrompt = finished
            } else if newValue != nil {
                openAfterPrompt = nil
            }
        }
    }

    private func openCreate() {
        modalOpen = true
        showCreate = true
    }

    private func openJoin() {
        modalOpen = true
        showJoin = true
    }

    private func createDismissed() {
        if let newID = createdID {
            createdID = nil
            // Keep modalOpen: the invite sheet follows right away, then we open the group.
            openAfterInvite = newID
            invite = GroupSheetTarget(id: newID)
        } else {
            modalOpen = false
        }
    }

    private func inviteDismissed() {
        modalOpen = false
        guard let groupID = openAfterInvite else { return }
        openAfterInvite = nil
        show(groupID)
    }

    private func promptBinding(_ target: GroupSheetTarget?) -> Binding<GroupSheetTarget?> {
        Binding<GroupSheetTarget?>(
            get: { target },
            set: { newValue in
                if newValue == nil {
                    store.pendingVowPrompt = nil
                }
            }
        )
    }

    private func promptDismissed() {
        guard let groupID = openAfterPrompt else { return }
        openAfterPrompt = nil
        show(groupID)
    }

    private func show(_ groupID: GroupID) {
        guard store.groupIDs.contains(groupID) else { return }
        if path.last != groupID {
            path = [groupID]
        }
    }
}
