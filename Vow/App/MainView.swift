import SwiftUI

struct MainView: View {
    @Environment(VowStore.self) private var store
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AmbientBackground()
            scroll
        }
        .overlay(alignment: .top) {
            toastOverlay
        }
        .onChange(of: store.toast) { _, newValue in
            handleToast(newValue)
        }
        .onAppear {
            handleToast(store.toast)
        }
        .onDisappear {
            toastTask?.cancel()
        }
    }

    private var scroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let state = store.state {
                MainColumn(
                    state: state,
                    theme: store.theme,
                    rows: store.crewRows,
                    onSealed: { store.seal() }
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            DemoBar()
        }
    }

    private var toastOverlay: some View {
        VStack(spacing: 0) {
            if let text = toastText {
                Toast(text: text)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: toastText)
    }

    private func handleToast(_ value: String?) {
        guard let text = value else { return }
        store.toast = nil
        toastTask?.cancel()
        toastText = text
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if Task.isCancelled { return }
            toastText = nil
        }
    }
}

/// The single scrolling column. Everything above the orb has fixed height in both states.
private struct MainColumn: View {
    let state: VowState
    let theme: DailyTheme
    let rows: [CrewMemberRow]
    let onSealed: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HeaderView(cycle: state.cycle, day: state.day)
            VowCard(state: state)
            CreedLine(glyphNumber: theme.glyphNumber, creed: theme.creed, sealed: state.sealedToday)
            orb
            StreakCard(
                streak: state.liveStreak,
                best: max(state.bestStreak, state.liveStreak),
                history: state.history,
                sealedToday: state.sealedToday
            )
            CrewCard(crewTitle: state.crew.title, rows: rows)
            PotCard(stake: state.stake, cyclePot: state.cyclePot, pot: state.pot, net: state.net)
            LedgerCard(entries: state.ledger, stake: state.stake)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    private var orb: some View {
        OrbView(theme: theme, sealed: state.sealedToday, onSealed: onSealed)
            .frame(width: 220, height: 220)
            .id("\(state.cycle)-\(state.day)")
            .frame(maxWidth: .infinity)
            .zIndex(1)
    }
}
