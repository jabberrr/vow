import Foundation

/// JSON cache of the last known group snapshots (Application Support/vow-cache.json), so the app opens instantly
/// and works read-only offline. It is read once, at launch. Saving leaves the main thread at once: the store hands
/// over its snapshots as they are, and a serial queue leaves out what is still pending, encodes and writes, in
/// order. Encoding every group after each change otherwise holds the main thread for as long as that takes, which
/// grows with every record ever made. A save that a newer save or a clear has overtaken before it began is
/// skipped. Failures are ignored.
final class SnapshotCache: @unchecked Sendable {
    struct Payload: Codable {
        var userID: String?
        var order: [GroupID]
        var snapshots: [GroupSnapshot]
    }

    static let fileName: String = "vow-cache.json"

    private let queue: DispatchQueue = DispatchQueue(label: "app.dabora.vow.snapshot-cache", qos: .utility)
    private let lock: NSLock = NSLock()
    /// Counts saves and clears: a queued save goes ahead only while its count is still the latest. Only under
    /// `lock`.
    private var latest: Int = 0

    private var fileURL: URL? {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir.appendingPathComponent(SnapshotCache.fileName)
    }

    func load() -> Payload? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Records still pending (no server date yet) are never cached: they would outlive their save attempt.
    func save(_ payload: Payload) {
        let ticket: Int = advance()
        queue.async {
            guard self.isLatest(ticket) else { return }
            let confirmed: Payload = SnapshotCache.withoutPending(payload)
            guard let url: URL = self.fileURL, let data: Data = try? JSONEncoder().encode(confirmed) else { return }
            try? data.write(to: url, options: [.atomic])
        }
    }

    /// Deletes the file once a save already under way has ended; saves not yet begun are dropped.
    func clear() {
        _ = advance()
        queue.async {
            guard let url: URL = self.fileURL else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    private func advance() -> Int {
        lock.lock()
        defer { lock.unlock() }
        latest += 1
        return latest
    }

    private func isLatest(_ ticket: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ticket == latest
    }

    private static func withoutPending(_ payload: Payload) -> Payload {
        var snapshots: [GroupSnapshot] = []
        for snapshot in payload.snapshots {
            var s: GroupSnapshot = snapshot
            s.checkIns.removeAll(where: { (c: CheckInInfo) -> Bool in c.serverDate == nil })
            s.excuses.removeAll(where: { (e: ExcuseInfo) -> Bool in e.serverDate == nil })
            s.votes.removeAll(where: { (v: VoteInfo) -> Bool in v.serverDate == nil })
            s.posts.removeAll(where: { (p: PostInfo) -> Bool in p.serverDate == nil })
            s.reactions.removeAll(where: { (r: ReactionInfo) -> Bool in r.serverDate == nil })
            snapshots.append(s)
        }
        return Payload(userID: payload.userID, order: payload.order, snapshots: snapshots)
    }
}
