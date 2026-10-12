import SwiftUI

/// Home content: balance, groups, new / join. Lives inside HomeView's NavigationStack.
struct HomeScreen: View {
    let onCreate: () -> Void
    let onJoin: () -> Void

    @Environment(AppStore.self) private var store

    /// The unlit orb on the empty state.
    private static let emptyTheme: DailyTheme = DailyTheme.make(cycle: 1, day: 1)

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                column
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
            .refreshable {
                await store.refreshAll()
            }
        }
        .screenBackground()
        // Not displayed; gives pushed screens a meaningful back label for VoiceOver.
        .navigationTitle("Vow")
        // The logo and gear live in the content: a large logo in the nav bar gets collapsed into an
        // overflow "•••" button on iOS 26, so Home shows no navigation bar at all.
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var column: some View {
        if store.groupIDs.isEmpty {
            emptyColumn
        } else {
            groupsColumn
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s) {
            Text("Vow")
                .font(Typeface.wordmark)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s)
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(Palette.text3)
                    .transition(.opacity)
            }
            settingsLink
        }
        .frame(minHeight: Space.hitTarget)
        .padding(.top, Space.xs)
        .animation(Motion.fade, value: store.isRefreshing)
    }

    /// 44pt target; the glyph's right edge lines up with the content edge.
    private var settingsLink: some View {
        NavigationLink {
            SettingsView()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Palette.text2)
                .frame(width: Space.hitTarget, height: Space.hitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Settings")
        .padding(.trailing, -Space.m)
    }

    // MARK: With groups

    private var groupsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            balance
                .padding(.top, Space.l)
            failureBanner
            SectionHeader("Groups")
                .padding(.top, Space.section)
            groupList
                .padding(.top, 10)
            groupActions
                .padding(.top, Space.xl)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.huge)
    }

    private var balance: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Balance")
                .font(Typeface.subheadline)
                .foregroundStyle(Palette.text2)
            HeroNumber(value: store.totalBalance)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var failureBanner: some View {
        if case .failed(let message) = store.phase {
            Banner(systemImage: "exclamationmark.icloud", text: message, actionTitle: "Try again", action: retry)
                .padding(.top, Space.xxl)
        }
    }

    private var groupList: some View {
        VStack(spacing: 0) {
            ForEach(store.groupIDs, id: \.self) { groupID in
                groupLink(groupID)
            }
        }
        .card()
    }

    @ViewBuilder
    private func groupLink(_ groupID: GroupID) -> some View {
        if groupID != store.groupIDs.first {
            InsetDivider(leading: 66)
        }
        NavigationLink(value: groupID) {
            GroupRow(id: groupID)
        }
        .buttonStyle(RowStyle())
    }

    /// Side by side; stacked when the labels don't fit (small phones, large text).
    private var groupActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.m) {
                newGroupButton
                joinButton
            }
            VStack(spacing: Space.m) {
                newGroupButton
                joinButton
            }
        }
    }

    private var newGroupButton: some View {
        SecondaryButton("New group", systemImage: "plus", action: onCreate)
    }

    private var joinButton: some View {
        SecondaryButton("Join with link", systemImage: "link", action: onJoin)
    }

    // MARK: Empty

    private var emptyColumn: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: Space.huge)
            emptyState
            Spacer(minLength: Space.huge)
            PrimaryButton("New group", action: onCreate)
            joinButton
                .padding(.top, Space.m)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.bottom, Space.l)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            DormantOrb(theme: HomeScreen.emptyTheme, size: 112)
            Text("No groups yet")
                .font(Typeface.title3)
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 28)
        }
        .frame(maxWidth: .infinity)
    }

    private func retry() {
        Task { await store.bootstrap() }
    }
}
