import SwiftUI
import UIKit

/// Fixed glass bar pinned to the bottom (via safeAreaInset in MainView).
struct DemoBar: View {
    @Environment(VowStore.self) private var store
    @State private var confirmReset: Bool = false

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
        .confirmationDialog("Reset Vow?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset everything", role: .destructive) {
                store.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears your vow, streak, pot and ledger.")
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
            store.advanceDay()
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
        }
        .buttonStyle(.plain)
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
    }
}
