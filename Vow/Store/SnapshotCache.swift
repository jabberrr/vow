import Foundation

/// JSON cache of the last known group snapshots (Application Support/vow-cache.json),
/// so the app opens instantly and works read-only offline. Failures are ignored.
struct SnapshotCache {
    struct Payload: Codable {
        var userID: String?
        var order: [GroupID]
        var snapshots: [GroupSnapshot]
    }

    static let fileName: String = "vow-cache.json"

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

    func save(_ payload: Payload) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
