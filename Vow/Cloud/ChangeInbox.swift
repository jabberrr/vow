import Foundation

/// Main-thread mailbox for CloudKit's silent pushes: something changed in a database the app subscribes to
/// (`CloudService.ensureSubscriptions`). The app delegate delivers each push with what iOS waits for; the store
/// installs the handler once it has an account, just before its first refresh. A push that comes before then is
/// answered at once, as nothing new: that first refresh fetches the change anyway, and a launch in the background
/// may never get that far, so holding the answer back could leave iOS waiting.
@MainActor
enum ChangeInbox {
    /// Refreshes every group (a push doesn't say which changed) and says whether anything came in.
    static var handler: (@MainActor () async -> Bool)? = nil

    /// How long a push waits for its refresh. iOS gives a silent push about 30 s and ends the app if it hasn't
    /// been answered by then, while a refresh that starts behind a running one waits for that one too.
    static let deadlineNanos: UInt64 = 25_000_000_000

    /// Calls `done` exactly once, on the main thread: with whether the refresh brought anything new, or with false
    /// once `deadlineNanos` has passed. A refresh past the deadline carries on.
    static func deliver(_ done: @escaping (Bool) -> Void) {
        guard let refresh = handler else {
            done(false)
            return
        }
        let answer: PushAnswer = PushAnswer(done)
        let deadline: Task<Void, Never> = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ChangeInbox.deadlineNanos)
            answer.send(false)
        }
        Task { @MainActor in
            let changed: Bool = await refresh()
            deadline.cancel()
            answer.send(changed)
        }
    }
}

/// One push's answer: the first `send` reaches iOS, and any later one does nothing.
@MainActor
private final class PushAnswer {
    private var done: ((Bool) -> Void)?

    init(_ done: @escaping (Bool) -> Void) {
        self.done = done
    }

    func send(_ changed: Bool) {
        guard let reply: (Bool) -> Void = done else { return }
        done = nil
        reply(changed)
    }
}
