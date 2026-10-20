import SwiftUI
import Observation

/// Every sheet the main shell can show. One at a time, and only through `Presenter`.
enum MainSheet: Identifiable, Equatable {
    case create
    case join
    case invite(GroupID)
    case vow(GroupID)
    case member(GroupID, String)
    case settings
    case profile
    case reminderOffer

    var id: String {
        switch self {
        case .create: return "create"
        case .join: return "join"
        case .invite(let g): return "invite-" + g.zoneName
        case .vow(let g): return "vow-" + g.zoneName
        case .member(let g, let u): return "member-" + g.zoneName + "-" + u
        case .settings: return "settings"
        case .profile: return "profile"
        case .reminderOffer: return "reminderOffer"
        }
    }
}

/// Confirmations on the main screen. They are UIKit presentations too, so they share the sheet's slot.
enum MainDialog: Equatable {
    case leave(GroupID)
    case delete(GroupID)
    case resetTest(GroupID)
}

/// Who asked for a presentation.
enum PresentSource: Equatable {
    /// A tap on the main screen: top bar, tab bar, sidebar row, page content. A tap can only reach the
    /// screen when nothing modal covers it, so whatever still counts as up is closed first.
    case screen
    /// An item of a SwiftUI `Menu` on the main screen. The menu closes as a UIKit presentation with no
    /// callback, so the request also waits for that.
    case menu
    /// A control in the sheet or dialog that is up (Invite after Create, Edit vow from your member sheet).
    /// That one closes first.
    case sheet
    /// The app itself (the vow prompt after joining, the reminder offer). Waits until nothing is up or
    /// asked for and the shell is not busy; never interrupts.
    case automatic
}

/// The one owner of the main shell's sheet and confirmation dialog.
///
/// idle → presenting (the sheet is set) → shown (its content's onAppear) → dismissing (cleared) → idle
/// (onDismiss or the content's onDisappear, whichever comes first). A dialog counts as shown once it is set.
/// Presenting and dismissing end on a deadline with no callback: a sheet that never appears is cleared and
/// tried once more, and one that never reports its dismissal is taken as gone. Shown ends by the user, or
/// by the next request, which closes it first. Nothing is set in the update that cleared something, nor
/// within a settle pause of it.
@MainActor
@Observable
final class Presenter {
    private enum Modal: Equatable {
        case sheet(MainSheet)
        case dialog(MainDialog)
    }

    private enum Phase: Equatable {
        case idle
        /// `sheet` is set; its content's onAppear has not come yet.
        case presenting(MainSheet, automatic: Bool)
        case shown(Modal)
        /// `sheet` is cleared; neither onDismiss nor the content's onDisappear has come yet. Carries the
        /// sheet if it had appeared, for `didClose`.
        case dismissing(MainSheet?)
    }

    /// Read by `.sheet(item:)` through `sheetBinding`. Only this class writes it.
    private(set) var sheet: MainSheet? = nil
    /// Read by `.confirmationDialog` through `dialogBinding` and `presenting:`.
    private(set) var dialog: MainDialog? = nil
    /// Nothing up, coming, going or asked for: the screen can be seen (the morning reveal waits for this).
    private(set) var isIdle: Bool = true

    /// Asked just before an automatic request shows; by then the prompt may no longer apply.
    @ObservationIgnored var isStillWanted: (MainSheet) -> Bool = { (_: MainSheet) -> Bool in
        return true
    }
    /// Once a sheet that appeared has gone, by any route: swipe, close button, replacement, deadline.
    @ObservationIgnored var didClose: (MainSheet) -> Void = { (_: MainSheet) -> Void in }

    @ObservationIgnored private var phase: Phase = .idle
    /// Uptime when `phase` began; its deadlines count from here.
    @ObservationIgnored private var phaseStart: TimeInterval = 0
    /// The user's latest request; it replaces an older one and closes whatever is up.
    @ObservationIgnored private var userPending: Modal? = nil
    /// The app's requests, oldest first, each once.
    @ObservationIgnored private var automatic: [MainSheet] = []
    /// `dismissAll` arrived while something was up or coming up.
    @ObservationIgnored private var closeRequested: Bool = false
    /// The sheet whose presentation has already failed once; a second failure is final.
    @ObservationIgnored private var retrying: MainSheet? = nil
    @ObservationIgnored private var isActive: Bool = false
    @ObservationIgnored private var isBusy: Bool = false
    /// Uptime before which nothing starts: the last modal leaving, the shell fading in, the sidebar sliding,
    /// a menu closing.
    @ObservationIgnored private var quietUntil: TimeInterval = 0
    @ObservationIgnored private var wakeTask: Task<Void, Never>? = nil

    /// A sheet that was set must have appeared, and one that was cleared must be gone, by then.
    private static let deadline: TimeInterval = 1
    /// A sheet is never closed sooner than this after it appeared: its present animation is still running.
    private static let minShown: TimeInterval = 0.5
    /// After a sheet has gone, before the next presentation (well over a frame).
    private static let settle: TimeInterval = 0.15
    /// An action sheet's fade-out; also the pause before retrying a refused sheet.
    private static let dialogSettle: TimeInterval = 0.35
    /// The longest SwiftUI `Menu` close, iOS 26's morph back into its label included.
    private static let menuClose: TimeInterval = 0.45

    /// Uptime, not the wall clock: changing the clock can't stretch a deadline.
    private static var now: TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }

    // MARK: - Requests

    func present(_ s: MainSheet, from source: PresentSource) {
        if source == .automatic {
            if !automatic.contains(s) {
                automatic.append(s)
            }
            step()
            return
        }
        request(.sheet(s), from: source)
    }

    /// Leave, delete, reset: from `.screen` or `.menu`.
    func confirm(_ d: MainDialog, from source: PresentSource) {
        request(.dialog(d), from: source)
    }

    /// A reminder tap: whatever is up or coming up closes, and the user's waiting request is dropped.
    func dismissAll() {
        userPending = nil
        if phase != .idle {
            closeRequested = true
        }
        step()
    }

    // MARK: - Shell state

    /// False until the shell is on screen, and while its scene is not active: nothing starts.
    func setActive(_ active: Bool) {
        isActive = active
        step()
    }

    /// An orb hold, the reward cascade or the open sidebar: automatic requests wait.
    func setBusy(_ busy: Bool) {
        isBusy = busy
        step()
    }

    /// Nothing starts for `seconds` more: the shell fading in, the sidebar sliding.
    func delay(for seconds: TimeInterval) {
        quiet(for: seconds)
        step()
    }

    // MARK: - Bindings

    /// SwiftUI writes nil on a swipe, on `dismiss()` and on a tap on the dimmed background.
    var sheetBinding: Binding<MainSheet?> {
        return Binding<MainSheet?>(
            get: { [weak self] () -> MainSheet? in
                return self?.sheet
            },
            set: { [weak self] (value: MainSheet?) -> Void in
                if value == nil {
                    self?.sheetCleared()
                }
            }
        )
    }

    var dialogBinding: Binding<Bool> {
        return Binding<Bool>(
            get: { [weak self] () -> Bool in
                return self?.dialog != nil
            },
            set: { [weak self] (value: Bool) -> Void in
                if !value {
                    self?.dialogEnded()
                }
            }
        )
    }

    // MARK: - Sheet callbacks

    /// The sheet content's onAppear: the only proof that a presentation really happened.
    func sheetAppeared(_ s: MainSheet) {
        guard case .presenting(let current, _) = phase, current == s else { return }
        retrying = nil
        enter(.shown(.sheet(s)))
        step()
    }

    /// The sheet content's onDisappear. Also catches a sheet UIKit took down without telling SwiftUI.
    func sheetDisappeared(_ s: MainSheet) {
        switch phase {
        case .shown(.sheet(let current)) where current == s:
            finish(after: Presenter.settle)
        case .dismissing:
            finish(after: Presenter.settle)
        default:
            break
        }
    }

    /// `.sheet(onDismiss:)` names no sheet, so it only completes a dismissal already under way.
    func sheetDismissed() {
        guard case .dismissing = phase else { return }
        finish(after: Presenter.settle)
    }

    // MARK: - State machine

    private func request(_ m: Modal, from source: PresentSource) {
        if source == .menu {
            quiet(for: Presenter.menuClose)
        }
        switch phase {
        case .presenting(let s, _):
            // Still coming up: the same request again is a double tap.
            if m != Modal.sheet(s) {
                userPending = m
            }
        case .shown(let current):
            // From the screen even the same one counts: the tap shows that what is "up" is stale.
            if m != current || source != .sheet {
                userPending = m
            }
        case .idle, .dismissing:
            userPending = m
        }
        step()
    }

    /// Goes as far as the phase allows now, and wakes itself when it can go further. Safe to call any time.
    private func step() {
        defer {
            let idle: Bool = phase == .idle && userPending == nil
            if isIdle != idle {
                isIdle = idle
            }
        }
        switch phase {
        case .idle:
            let hasWork: Bool = userPending != nil || (!isBusy && !automatic.isEmpty)
            guard isActive, hasWork else { return }
            if Presenter.now < quietUntil {
                wake(at: quietUntil)
                return
            }
            startNext()
        case .presenting(let s, let isAutomatic):
            guard isDue(Presenter.deadline) else { return }
            presentationFailed(s, isAutomatic: isAutomatic)
        case .shown(let m):
            guard closeRequested || userPending != nil, isDue(Presenter.minShown) else { return }
            close(m)
        case .dismissing:
            // Cleared, but neither onDismiss nor onDisappear came: it is gone.
            guard isDue(Presenter.deadline) else { return }
            finish(after: Presenter.settle)
        }
    }

    /// The user's request first; then the oldest automatic one that still applies, unless the shell is busy.
    private func startNext() {
        if let m: Modal = userPending {
            userPending = nil
            start(m, isAutomatic: false)
            return
        }
        guard !isBusy else { return }
        while let s: MainSheet = automatic.first {
            automatic.removeFirst()
            if isStillWanted(s) {
                start(.sheet(s), isAutomatic: true)
                return
            }
        }
    }

    private func start(_ m: Modal, isAutomatic: Bool) {
        switch m {
        case .sheet(let s):
            sheet = s
            enter(.presenting(s, automatic: isAutomatic))
        case .dialog(let d):
            dialog = d
            enter(.shown(m))
        }
        step()
    }

    /// A sheet waits for its dismissal callbacks; a dialog has none worth waiting for.
    private func close(_ m: Modal) {
        switch m {
        case .sheet(let s):
            sheet = nil
            enter(.dismissing(s))
            step()
        case .dialog:
            finish(after: Presenter.dialogSettle)
        }
    }

    /// SwiftUI cleared the sheet itself.
    private func sheetCleared() {
        switch phase {
        case .presenting:
            sheet = nil
            enter(.dismissing(nil))
            step()
        case .shown(.sheet(let s)):
            close(.sheet(s))
        default:
            break
        }
    }

    private func dialogEnded() {
        guard case .shown(.dialog(_)) = phase else { return }
        finish(after: Presenter.dialogSettle)
    }

    /// Set but never shown: UIKit refused it (a menu or dialog was still closing). It is tried once more,
    /// with its own source, unless it was dismissed meanwhile or the user has asked for something else.
    private func presentationFailed(_ s: MainSheet, isAutomatic: Bool) {
        let retry: Bool = retrying != s && !closeRequested
        retrying = retry ? s : nil
        if retry && isAutomatic && !automatic.contains(s) {
            automatic.insert(s, at: 0)
        } else if retry && !isAutomatic && userPending == nil {
            userPending = .sheet(s)
        }
        finish(after: Presenter.dialogSettle)
    }

    /// Back to idle from any phase; nothing new starts for `seconds`. `didClose` runs after the pause is
    /// set, so a request it makes waits too.
    private func finish(after seconds: TimeInterval) {
        var closed: MainSheet? = nil
        switch phase {
        case .shown(.sheet(let s)):
            closed = s
        case .dismissing(let s):
            closed = s
        default:
            break
        }
        if sheet != nil {
            sheet = nil
        }
        if dialog != nil {
            dialog = nil
        }
        closeRequested = false
        enter(.idle)
        quiet(for: seconds)
        if let s: MainSheet = closed {
            didClose(s)
        }
        step()
    }

    private func enter(_ p: Phase) {
        phase = p
        phaseStart = Presenter.now
    }

    private func quiet(for seconds: TimeInterval) {
        quietUntil = max(quietUntil, Presenter.now + seconds)
    }

    /// Whether `seconds` have passed since the phase began; if not, `step` runs again once they have.
    private func isDue(_ seconds: TimeInterval) -> Bool {
        let due: TimeInterval = phaseStart + seconds
        if Presenter.now >= due {
            return true
        }
        wake(at: due)
        return false
    }

    /// One timer serves every phase: when it fires, `step` checks again whatever is waiting.
    private func wake(at uptime: TimeInterval) {
        wakeTask?.cancel()
        let nanos: UInt64 = UInt64(max(uptime - Presenter.now, 0) * 1_000_000_000)
        wakeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return }
            self?.step()
        }
    }
}
