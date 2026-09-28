import SwiftUI
import UIKit
import Observation

/// Owns the hold interaction: press/release bookkeeping, the completion and seal work items,
/// the haptic and the sound calls. Views only READ `phase` / `burstStart`; nothing in here is
/// ever called from a TimelineView body.
@Observable
final class OrbHoldController {
    /// Visual snapshot of the interaction (read by the TimelineView, never written from it).
    private(set) var phase: OrbPhase = OrbPhase()
    /// Non-nil while the burst overlay should stay mounted.
    private(set) var burstStart: Date? = nil

    @ObservationIgnored private var isPressing: Bool = false
    @ObservationIgnored private var didComplete: Bool = false
    @ObservationIgnored private var didSeal: Bool = false
    @ObservationIgnored private var completeWork: DispatchWorkItem? = nil
    @ObservationIgnored private var sealWork: DispatchWorkItem? = nil
    @ObservationIgnored private var burstWork: DispatchWorkItem? = nil
    @ObservationIgnored private var pendingSeal: (() -> Void)? = nil
    @ObservationIgnored private var haptic: UIImpactFeedbackGenerator? = nil

    init() {}

    // MARK: - Gesture entry points (main thread)

    /// Called on every DragGesture.onChanged; only the first call of a touch does anything.
    func begin(onSealed: @escaping () -> Void) {
        guard !isPressing, !didComplete else { return }
        isPressing = true

        let generator: UIImpactFeedbackGenerator = haptic ?? UIImpactFeedbackGenerator(style: .heavy)
        haptic = generator
        generator.prepare()

        phase = OrbPhase(pressStart: Date(), releasedAt: nil, progressAtRelease: 0, completedAt: nil)
        SoundEngine.shared.startBuildup(duration: OrbTiming.hold)

        completeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.complete(onSealed: onSealed)
        }
        completeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + OrbTiming.hold, execute: work)
    }

    /// Called on DragGesture.onEnded and when the gesture state resets (cancellation). Idempotent.
    func release() {
        guard isPressing else { return }
        isPressing = false
        if didComplete { return }

        completeWork?.cancel()
        completeWork = nil
        SoundEngine.shared.stopBuildup()

        let now = Date()
        let p: Double = phase.progress(at: now)
        phase = OrbPhase(pressStart: nil, releasedAt: now, progressAtRelease: p, completedAt: nil)
    }

    /// Abort an in-flight hold without completing (e.g. sealed was set externally).
    func cancelHold() {
        guard !didComplete else { return }
        completeWork?.cancel()
        completeWork = nil
        if isPressing {
            SoundEngine.shared.stopBuildup()
        }
        isPressing = false
        phase = OrbPhase()
    }

    /// Full reset for a fresh day (sealed flipped back to false).
    func reset() {
        completeWork?.cancel()
        sealWork?.cancel()
        burstWork?.cancel()
        completeWork = nil
        sealWork = nil
        burstWork = nil
        pendingSeal = nil
        if isPressing {
            SoundEngine.shared.stopBuildup()
        }
        isPressing = false
        didComplete = false
        didSeal = false
        phase = OrbPhase()
        burstStart = nil
    }

    /// onDisappear: cancel everything pending. A completed-but-not-yet-delivered seal is
    /// delivered now rather than lost (still exactly once, guarded by `didSeal`).
    func teardown() {
        completeWork?.cancel()
        completeWork = nil
        burstWork?.cancel()
        burstWork = nil
        burstStart = nil
        if isPressing && !didComplete {
            SoundEngine.shared.stopBuildup()
            phase = OrbPhase()
        }
        isPressing = false

        sealWork?.cancel()
        sealWork = nil
        if let seal = pendingSeal {
            pendingSeal = nil
            deliverSeal(seal)
        }
    }

    // MARK: - Completion (runs from the DispatchWorkItem, main thread)

    private func complete(onSealed: @escaping () -> Void) {
        guard isPressing, !didComplete else { return }
        didComplete = true
        completeWork = nil

        let now = Date()
        phase = OrbPhase(pressStart: phase.pressStart, releasedAt: nil, progressAtRelease: 1, completedAt: now)
        burstStart = now

        haptic?.impactOccurred()
        SoundEngine.shared.stopBuildup()
        SoundEngine.shared.pop()

        pendingSeal = onSealed
        let seal = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.sealWork = nil
            guard let callback = self.pendingSeal else { return }
            self.pendingSeal = nil
            self.deliverSeal(callback)
        }
        sealWork = seal
        DispatchQueue.main.asyncAfter(deadline: .now() + OrbTiming.sealDelay, execute: seal)

        let endBurst = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.burstWork = nil
            self.burstStart = nil
        }
        burstWork = endBurst
        DispatchQueue.main.asyncAfter(deadline: .now() + OrbTiming.burstDuration, execute: endBurst)
    }

    private func deliverSeal(_ callback: () -> Void) {
        guard !didSeal else { return }
        didSeal = true
        callback()
    }
}
