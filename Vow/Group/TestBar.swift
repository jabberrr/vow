import SwiftUI
import UIKit

/// Floating capsule pinned to the bottom of a test group you own (via safeAreaInset in GroupView).
/// GroupView dims it with the room during a hold.
struct TestBar: View {
    let id: GroupID

    @Environment(AppStore.self) private var store
    @State private var confirmReset: Bool = false
    @State private var busy: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            advanceButton
            resetButton
        }
        .padding(6)
        .background(barBackground)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .confirmationDialog("Reset this test group?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset group", role: .destructive) {
                run { await store.resetTestGroup(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everyone starts over from day 1. Check-ins, streaks and points are cleared.")
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

    /// Material capsule with an overlay tint, a hairline and the floating shadow.
    private var barBackground: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10)
            Capsule()
                .fill(Palette.overlay.opacity(0.55))
            Capsule()
                .strokeBorder(Palette.hairline, lineWidth: 1)
        }
    }

    private var advanceButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            run { await store.advanceTestDay(id) }
        } label: {
            PrimaryLabel(title: "Next day", systemImage: "forward.fill", busy: busy)
        }
        .buttonStyle(PressableStyle())
        .disabled(busy)
    }

    private var resetButton: some View {
        Button {
            confirmReset = true
        } label: {
            SecondaryLabel(title: "Reset")
                .frame(width: 96)
        }
        .buttonStyle(PressableStyle())
        .disabled(busy)
    }
}
