import SwiftUI

/// Home content: balance, groups, create / join. Lives inside HomeView's NavigationStack.
struct HomeScreen: View {
    let onCreate: () -> Void
    let onJoin: () -> Void

    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView(.vertical, showsIndicators: false) {
                column
            }
            .refreshable {
                await store.refreshAll()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Vow")
                    .font(Theme.display(28, .heavy))
                    .gradientText()
            }
            ToolbarItem(placement: .topBarTrailing) {
                settingsLink
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var settingsLink: some View {
        NavigationLink {
            SettingsView()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))
        }
        .accessibilityLabel("Settings")
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 16) {
            BalanceCard(balance: store.totalBalance, groupCount: store.groupIDs.count)
            failureBanner
            groupsHeader
            groupsList
            actions
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 32)
    }

    @ViewBuilder
    private var failureBanner: some View {
        if case .failed(let message) = store.phase {
            HStack(alignment: .center, spacing: 12) {
                Text(message)
                    .font(Theme.mono(12, .medium))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Retry") {
                    Task { await store.bootstrap() }
                }
                .font(Theme.display(14, .semibold))
                .foregroundStyle(Theme.cyan)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 14, radius: 18)
        }
    }

    private var groupsHeader: some View {
        HStack(spacing: 8) {
            Text("Your groups")
                .eyebrow()
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Color.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 18)
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var groupsList: some View {
        if store.groupIDs.isEmpty {
            EmptyGroupsCard()
        } else {
            VStack(spacing: 12) {
                ForEach(store.groupIDs, id: \.self) { groupID in
                    NavigationLink(value: groupID) {
                        GroupRow(id: groupID)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Create group", action: onCreate)
            SecondaryButton(title: "Join with link", systemImage: "link", action: onJoin)
        }
        .padding(.top, 4)
    }
}

private struct EmptyGroupsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No groups yet")
                .font(Theme.display(19, .semibold))
                .foregroundStyle(Color.white)
            step("1", "Create a group, pick a daily stake and share the invite link.")
            step("2", "Everyone swears their own vow and holds the orb each day.")
            step("3", "Miss a day and your stake goes to the ones who kept theirs.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(Theme.mono(12, .bold))
                .foregroundStyle(Theme.cyan)
            Text(text)
                .font(Theme.display(15, .regular))
                .foregroundStyle(Color.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
