import Foundation
import Observation

/// Which of a post's two assets to load: the small JPEG the chat shows, or the full photo or video.
enum MediaAssetKey: String {
    case thumb
    case media
}

/// Post photos and videos on disk, under Caches/vow-media/<zone>/<postID>-<key>.<ext>. A file is downloaded the
/// first time it's asked for, and requests that arrive while it downloads share that one download. Your own
/// uploads are adopted from their draft, so they show at once and are never downloaded.
@MainActor
@Observable
final class MediaCache {
    static let shared: MediaCache = MediaCache()

    private static let root: URL = URL.cachesDirectory.appendingPathComponent("vow-media", isDirectory: true)

    /// Downloads in flight, by destination path.
    @ObservationIgnored private var downloads: [String: Task<URL?, Never>] = [:]
    /// Destination paths whose last download found nothing to fetch: the post has no such file, or the post or
    /// its group has gone. Trying again can't help, so the viewer says so instead of offering a retry.
    @ObservationIgnored private var unavailable: Set<String> = []

    /// Touches nothing, so merely referencing the cache never reaches CloudKit.
    private init() {}

    /// A local file for the post's asset: disk first, else downloaded once. nil for a text post, or when it can't
    /// be fetched (the next request tries again).
    func url(for post: PostInfo, key: MediaAssetKey, in id: GroupID) async -> URL? {
        guard let file = MediaCache.file(postID: post.id, kind: post.media, key: key, in: id) else { return nil }
        if FileManager.default.fileExists(atPath: file.path) {
            return file
        }
        let path: String = file.path
        if let running = downloads[path] {
            return await running.value
        }
        let task: Task<URL?, Never> = Task { () -> URL? in
            var fetched: URL? = nil
            var gone: Bool = false
            do {
                fetched = try await CloudService.shared.fetchAsset(postID: post.id, key: key, in: id)
            } catch {
                gone = (error as? CloudError) == .mediaMissing || CloudErrors.isGone(error)
            }
            // clearAll or remove cancelled this download and already forgot it.
            if Task.isCancelled { return nil }
            self.downloads[path] = nil
            if gone {
                self.unavailable.insert(path)
            } else {
                self.unavailable.remove(path)
            }
            guard let temporary = fetched, MediaCache.place(temporary, at: file) else { return nil }
            return file
        }
        downloads[path] = task
        return await task.value
    }

    /// Whether the last try at this asset found that it doesn't exist, as opposed to failing to reach it. Always
    /// true for a text post, which has none.
    func isUnavailable(_ post: PostInfo, key: MediaAssetKey, in id: GroupID) -> Bool {
        guard let file = MediaCache.file(postID: post.id, kind: post.media, key: key, in: id) else { return true }
        return unavailable.contains(file.path)
    }

    /// Your own upload: the draft's files are copied in as the post's entries, so it shows at once. The draft keeps
    /// its outbox files, which the upload reads and then discards.
    func adopt(_ draft: MediaDraft, postID: String, in id: GroupID) {
        if let thumb = MediaCache.file(postID: postID, kind: draft.kind, key: .thumb, in: id) {
            MediaCache.place(draft.thumbURL, at: thumb)
        }
        if let media = MediaCache.file(postID: postID, kind: draft.kind, key: .media, in: id) {
            MediaCache.place(draft.mediaURL, at: media)
        }
    }

    /// Deletes a post's files, whichever kind it was: a failed post you deleted. Its draft's outbox files are the
    /// store's to discard.
    func remove(postID: String, in id: GroupID) {
        for kind in [MediaKind.photo, MediaKind.video] {
            for key in [MediaAssetKey.thumb, MediaAssetKey.media] {
                guard let file = MediaCache.file(postID: postID, kind: kind, key: key, in: id) else { continue }
                downloads.removeValue(forKey: file.path)?.cancel()
                unavailable.remove(file.path)
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Deletes a group's folder, cancelling its downloads: you left or deleted the group, or it has gone.
    func removeGroup(_ id: GroupID) {
        guard MediaCache.isPlainName(id.zoneName) else { return }
        let folder: URL = MediaCache.root.appendingPathComponent(id.zoneName, isDirectory: true)
        let prefix: String = folder.path + "/"
        for path in Array(downloads.keys) where path.hasPrefix(prefix) {
            downloads.removeValue(forKey: path)?.cancel()
        }
        unavailable = unavailable.filter { (path: String) -> Bool in !path.hasPrefix(prefix) }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Deletes every cached file and the outbox ("Reset local data").
    func clearAll() {
        for task in downloads.values {
            task.cancel()
        }
        downloads.removeAll()
        unavailable.removeAll()
        try? FileManager.default.removeItem(at: MediaCache.root)
        try? FileManager.default.removeItem(at: MediaPrep.outbox)
    }

    // MARK: - Files

    /// nil for a text post, or for a name that isn't a plain file name: record names come from members' devices.
    private static func file(postID: String, kind: MediaKind, key: MediaAssetKey, in id: GroupID) -> URL? {
        guard kind != MediaKind.none, isPlainName(postID), isPlainName(id.zoneName) else { return nil }
        let ext: String = key == .media && kind == .video ? "mp4" : "jpg"
        return root.appendingPathComponent(id.zoneName, isDirectory: true)
            .appendingPathComponent(postID + "-" + key.rawValue)
            .appendingPathExtension(ext)
    }

    private static func isPlainName(_ name: String) -> Bool {
        return !name.isEmpty && name.allSatisfy { (c: Character) -> Bool in
            c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_")
        }
    }

    /// Copies `source` to `destination`, replacing any older copy. Never a move: CloudKit owns its downloads, and a
    /// draft's files are still to be uploaded. On APFS the copy is a clone, so it's instant and takes no space.
    @discardableResult
    private static func place(_ source: URL, at destination: URL) -> Bool {
        let fm: FileManager = FileManager.default
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: nil)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }
}
