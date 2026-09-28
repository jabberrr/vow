import SwiftUI

/// Public entry point for the orb. Occupies exactly 220x220 in BOTH states.
/// Press and hold for `OrbTiming.hold` to complete; `onSealed()` fires once, ~0.9s after completion.
struct OrbView: View {
    let theme: DailyTheme
    let sealed: Bool
    let onSealed: () -> Void

    @State private var hold: OrbHoldController = OrbHoldController()
    @State private var showSealed: Bool
    @GestureState private var touching: Bool = false

    init(theme: DailyTheme, sealed: Bool, onSealed: @escaping () -> Void) {
        self.theme = theme
        self.sealed = sealed
        self.onSealed = onSealed
        self._showSealed = State(initialValue: sealed)
    }

    var body: some View {
        ZStack {
            stateLayer
            burstLayer
        }
        .frame(width: 220, height: 220)
        .contentShape(Circle())
        .gesture(holdGesture, including: showSealed ? .subviews : .all)
        .onChange(of: touching) { _, isTouching in
            if !isTouching {
                hold.release()
            }
        }
        .onChange(of: sealed) { _, isSealed in
            handleSealedChange(isSealed)
        }
        .onAppear {
            if sealed && !showSealed {
                showSealed = true
            }
            if !showSealed {
                SoundEngine.shared.warmUp()
            }
        }
        .onDisappear {
            hold.teardown()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showSealed ? "Sealed for today" : "Press and hold to seal today")
    }

    @ViewBuilder
    private var stateLayer: some View {
        if showSealed {
            SealedOrb(theme: theme)
                .transition(.opacity)
        } else {
            ActiveOrb(theme: theme, phase: hold.phase)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var burstLayer: some View {
        if let start = hold.burstStart {
            OrbBurst(theme: theme, completedAt: start)
        }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, state, _ in
                state = true
            }
            .onChanged { _ in
                // begin() is idempotent per touch (guarded by isPressing / didComplete).
                if !showSealed {
                    hold.begin(onSealed: onSealed)
                }
            }
            .onEnded { _ in
                hold.release()
            }
    }

    private func handleSealedChange(_ isSealed: Bool) {
        if isSealed {
            hold.cancelHold()
            if !showSealed {
                withAnimation(.easeInOut(duration: OrbTiming.sealCrossfade)) {
                    showSealed = true
                }
            }
        } else {
            hold.reset()
            if showSealed {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showSealed = false
                }
            }
        }
    }
}
