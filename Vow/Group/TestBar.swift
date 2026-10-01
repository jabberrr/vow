import SwiftUI
import UIKit

/// Fixed glass bar pinned to the bottom of a test group you own (via safeAreaInset in GroupView).
struct TestBar: View {
    let id: GroupID

    @Environment(AppStore.self) private var store
    @State private var confirmReset: Bool = false
    @State private var busy: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            advanceButton
            resetButton
        }
        .padding(6)
        .background(barBackground)
        .overlay(Capsule().strokeBorder(Theme.rim, lineWidth: 0.75))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .confirmationDialog("Reset this test group?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset group", role: .destructive) {
                run { await store.resetTestGroup(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Starts over from day 1 for everyone. Check-ins, streaks and points so far are cleared.")
        }
    }

    private func run(_ work: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            await work()
            busy = false
        }
    }

    private var barBackground: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 10)
            Capsule()
                .fill(Color.white.opacity(0.05))
        }
    }

    private var advanceButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            run { await store.advanceTestDay(id) }
        } label: {
            Text("Advance to next day →")
                .font(Theme.display(15, .bold))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(Theme.brand))
                .contentShape(Capsule())
                .opacity(busy ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private var resetButton: some View {
        Button {
            confirmReset = true
        } label: {
            Text("Reset")
                .font(Theme.display(15, .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}
