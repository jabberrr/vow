import SwiftUI

/// Public entry point for the orb. Occupies exactly 220x220 in BOTH states.
/// Press and hold for `OrbTiming.hold` to complete; `onSealed()` fires once, ~0.9s after completion.
/// `onFocusChange` reports check-in focus (touch-down until the seal; the caller gates the room dim),
/// once per change. `onEarlyRelease` fires on a lift before completion that was not a scroll.
struct OrbView: View {
    let theme: DailyTheme
    let sealed: Bool
    let onSealed: () -> Void
    let onFocusChange: (Bool) -> Void
    let onEarlyRelease: () -> Void

    @State private var hold: OrbHoldController = OrbHoldController()
    @State private var showSealed: Bool
    /// The finger travelled past `moveSlop` within `moveWindow` of touch-down (a scroll attempt): the
    /// room stays lit for this touch, burst included. Cleared at the next hold's touch-down, not on lift.
    @State private var moved: Bool = false
    /// VoiceOver's "Check in" action asked for the seal; blocks a second request and a new hold.
    @State private var sealRequested: Bool = false
    /// Last value sent to `onFocusChange`, so a value is never reported twice in a row.
    @State private var reportedFocus: Bool = false
    @GestureState private var touching: Bool = false

    /// Travel (pt) after which a touch counts as a scroll for the room dim. The hold itself ignores it.
    private static let moveSlop: CGFloat = 10
    /// Movement only counts during the dim gate (0.2 s); after that the room follows the hold.
    private static let moveWindow: TimeInterval = Double(Motion.dimGateNanos) / 1_000_000_000

    init(theme: DailyTheme,
         sealed: Bool,
         onSealed: @escaping () -> Void,
         onFocusChange: @escaping (Bool) -> Void = { _ in },
         onEarlyRelease: @escaping () -> Void = {}) {
        self.theme = theme
        self.sealed = sealed
        self.onSealed = onSealed
        self.onFocusChange = onFocusChange
        self.onEarlyRelease = onEarlyRelease
        self._showSealed = State(initialValue: sealed)
    }

    var body: some View {
        orb
            .onChange(of: touching) { _, isTouching in
                if !isTouching {
                    hold.release()
                }
            }
            .onChange(of: isFocused) { _, focused in
                reportFocus(focused)
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
                // A day change mid-hold never leaves the room dark.
                hold.teardown()
                reportFocus(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(orbLabel)
            .accessibilityHint(orbHint)
            .accessibilityAddTraits(orbTraits)
            .accessibilityAction(named: "Check in") {
                checkInDirectly()
            }
    }

    private var orb: some View {
        ZStack {
            stateLayer
            burstLayer
        }
        .frame(width: 220, height: 220)
        .contentShape(Circle())
        .gesture(holdGesture, including: showSealed ? .subviews : .all)
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
            .onChanged { value in
                noteMovement(value)
                // begin() is idempotent per touch (guarded by isPressing / didComplete).
                if !showSealed && !sealRequested {
                    hold.begin(onSealed: onSealed)
                }
            }
            .onEnded { _ in
                // onEnded only runs on a real lift, not when a scroll cancels the drag.
                let early: Bool = isEarlyRelease
                hold.release()
                if early {
                    onEarlyRelease()
                }
            }
    }

    // MARK: - Focus

    /// True from touch-down until the seal crossfade starts, unless the touch began as a scroll.
    /// `moved` is fixed after the first 0.2 s and the burst keeps focus after a lift, so the value
    /// is the same just before and after completion: nothing is reported at the peak.
    private var isFocused: Bool {
        if showSealed || sealRequested || moved { return false }
        if hold.burstStart != nil { return true }
        return touching && hold.phase.completedAt == nil
    }

    /// A lift before completion that was not a scroll, on an orb that is not sealed or sealing.
    private var isEarlyRelease: Bool {
        !moved && !showSealed && !sealRequested && hold.burstStart == nil && hold.phase.completedAt == nil
    }

    /// Marks the touch as a scroll if it travels past `moveSlop` within `moveWindow` of the press.
    /// Later drift (iOS 18+ lets the orb's drag win over the scroll) never relights the room mid-hold.
    private func noteMovement(_ value: DragGesture.Value) {
        guard let start: Date = hold.phase.pressStart else {
            // First change of a new hold (before `begin`, translation ~0): forget the last touch.
            if moved {
                moved = false
            }
            return
        }
        guard !moved, value.time.timeIntervalSince(start) < OrbView.moveWindow else { return }
        let dx: CGFloat = value.translation.width
        let dy: CGFloat = value.translation.height
        if dx * dx + dy * dy > OrbView.moveSlop * OrbView.moveSlop {
            moved = true
        }
    }

    private func reportFocus(_ focused: Bool) {
        guard focused != reportedFocus else { return }
        reportedFocus = focused
        onFocusChange(focused)
    }

    // MARK: - Accessibility

    private var orbLabel: String {
        showSealed ? "Checked in today" : "Check in"
    }

    private var orbHint: String {
        showSealed ? "" : "Double-tap and hold to check in"
    }

    private var orbTraits: AccessibilityTraits {
        showSealed ? [] : [.isButton]
    }

    /// VoiceOver "Check in": seals directly, without the burst. Ignored once sealed, already
    /// requested, or when a completed hold is about to deliver the seal itself.
    private func checkInDirectly() {
        guard !showSealed, !sealRequested, hold.phase.completedAt == nil else { return }
        sealRequested = true
        // Stops an in-flight hold so it can't complete and seal a second time.
        hold.cancelHold()
        onSealed()
    }

    // MARK: - Sealed changes

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
            sealRequested = false
            if showSealed {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showSealed = false
                }
            }
        }
    }
}
