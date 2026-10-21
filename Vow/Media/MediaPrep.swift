import AVFoundation
import UIKit

/// A photo or video ready to send: files in the outbox, sized for a group chat, plus the shape the chat lays out
/// before anything has downloaded.
struct MediaDraft: Equatable {
    /// `.photo` or `.video`.
    let kind: MediaKind
    /// The prepared JPEG or MP4 in Caches/vow-outbox.
    let mediaURL: URL
    /// A JPEG at most 480 px on its long edge.
    let thumbURL: URL
    /// Width / height as shown, after orientation.
    let aspect: Double
    /// Seconds, for videos (at most `MediaPrep.videoLimit`).
    let duration: Double?
}

/// Why a photo or video couldn't be prepared.
enum MediaError: Error {
    /// The image or video can't be read, or has no picture.
    case unreadable
    /// The video couldn't be converted to MP4.
    case exportFailed
    /// A prepared file couldn't be written.
    case writeFailed
}

/// Turns a picked or captured photo or video into a draft in the outbox: photos upright and at most 1,600 px on the
/// long edge (JPEG 0.75), videos cut to their first `videoLimit` seconds and converted to MP4 at up to 960×540. Each
/// gets a thumbnail at most 480 px on the long edge (JPEG 0.7). Every member's media counts against the group owner's
/// iCloud storage, hence the tight budget. The work runs off the main actor.
enum MediaPrep {
    /// Drafts waiting to be sent. A draft is discarded once sent; "Reset local data" empties the folder.
    static let outbox: URL = URL.cachesDirectory.appendingPathComponent("vow-outbox", isDirectory: true)
    /// The longest video sent, in seconds; anything after it is cut. The camera's limit and the proof sheet's note
    /// read it too.
    static let videoLimit: Double = 20

    private static let photoLongEdge: CGFloat = 1_600
    private static let thumbLongEdge: CGFloat = 480
    private static let photoQuality: CGFloat = 0.75
    private static let thumbQuality: CGFloat = 0.7
    /// Where a video's thumbnail is taken: just past the first frame, which is often black.
    private static let thumbSeconds: Double = 0.1
    /// 960×540 first; a source that preset can't handle falls back to medium quality.
    private static let videoPresets: [String] = [AVAssetExportPreset960x540, AVAssetExportPresetMediumQuality]

    // MARK: - Photos

    static func photo(_ image: UIImage) async throws -> MediaDraft {
        let pixels: CGSize = pixelSize(image)
        guard pixels.width >= 1, pixels.height >= 1 else { throw MediaError.unreadable }
        let full: UIImage = redraw(image, longEdge: photoLongEdge)
        guard let media = full.jpegData(compressionQuality: photoQuality),
              let thumb = redraw(full, longEdge: thumbLongEdge).jpegData(compressionQuality: thumbQuality) else {
            throw MediaError.unreadable
        }
        let mediaURL: URL = try write(media, ext: "jpg")
        return try finish(.photo, mediaURL: mediaURL, thumb: thumb, aspect: Double(pixels.width / pixels.height),
                          duration: nil)
    }

    /// The size in pixels as shown: `UIImage.size` already accounts for orientation.
    private static func pixelSize(_ image: UIImage) -> CGSize {
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    /// The image drawn upright, at most `longEdge` px on its long side (never enlarged), at scale 1.
    private static func redraw(_ image: UIImage, longEdge: CGFloat) -> UIImage {
        let pixels: CGSize = pixelSize(image)
        let factor: CGFloat = min(1, longEdge / max(pixels.width, pixels.height))
        let size: CGSize = CGSize(width: max(1, (pixels.width * factor).rounded()),
                                  height: max(1, (pixels.height * factor).rounded()))
        let format: UIGraphicsImageRendererFormat = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer: UIGraphicsImageRenderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { (_: UIGraphicsImageRendererContext) in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Videos

    /// `url` must stay readable until this returns, so copy a picker's temporary file first.
    static func video(at url: URL) async throws -> MediaDraft {
        let asset: AVURLAsset = AVURLAsset(url: url)
        guard let shape = await measure(asset) else { throw MediaError.unreadable }
        let thumb: Data = try await videoThumbnail(asset, seconds: shape.seconds)
        let mediaURL: URL = try await export(asset, seconds: shape.seconds)
        return try finish(.video, mediaURL: mediaURL, thumb: thumb, aspect: shape.aspect,
                          duration: min(shape.seconds, videoLimit))
    }

    /// The video's shape as shown (its track's natural size turned by the preferred transform) and its length.
    private static func measure(_ asset: AVAsset) async -> (aspect: Double, seconds: Double)? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform),
              let length = try? await asset.load(.duration) else { return nil }
        let shown: CGSize = natural.applying(transform)
        let width: Double = abs(Double(shown.width))
        let height: Double = abs(Double(shown.height))
        let seconds: Double = CMTimeGetSeconds(length)
        guard width > 0, height > 0, seconds.isFinite, seconds > 0 else { return nil }
        return (aspect: width / height, seconds: seconds)
    }

    private static func videoThumbnail(_ asset: AVAsset, seconds: Double) async throws -> Data {
        let generator: AVAssetImageGenerator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbLongEdge, height: thumbLongEdge)
        let time: CMTime = CMTime(seconds: min(thumbSeconds, seconds / 2), preferredTimescale: 600)
        guard let frame = try? await generator.image(at: time).image,
              let data = UIImage(cgImage: frame).jpegData(compressionQuality: thumbQuality) else {
            throw MediaError.unreadable
        }
        return data
    }

    /// An MP4 of the first `videoLimit` seconds, laid out for streaming.
    private static func export(_ asset: AVAsset, seconds: Double) async throws -> URL {
        let output: URL = outboxFile(ext: "mp4")
        for preset in videoPresets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset),
                  session.supportedFileTypes.contains(.mp4) else { continue }
            session.outputURL = output
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true
            if seconds > videoLimit {
                session.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: videoLimit, preferredTimescale: 600))
            }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously {
                    cont.resume()
                }
            }
            if session.status == .completed {
                return output
            }
            try? FileManager.default.removeItem(at: output)
        }
        throw MediaError.exportFailed
    }

    // MARK: - Files

    /// Deletes a draft's files: once it has been sent, or when it's abandoned.
    static func discard(_ draft: MediaDraft) {
        try? FileManager.default.removeItem(at: draft.mediaURL)
        try? FileManager.default.removeItem(at: draft.thumbURL)
    }

    /// Writes the thumbnail beside the prepared media. If that fails the media goes too, so a failed draft leaves
    /// nothing in the outbox.
    private static func finish(_ kind: MediaKind, mediaURL: URL, thumb: Data, aspect: Double,
                               duration: Double?) throws -> MediaDraft {
        do {
            let thumbURL: URL = try write(thumb, ext: "jpg")
            return MediaDraft(kind: kind, mediaURL: mediaURL, thumbURL: thumbURL, aspect: aspect, duration: duration)
        } catch {
            try? FileManager.default.removeItem(at: mediaURL)
            throw error
        }
    }

    private static func write(_ data: Data, ext: String) throws -> URL {
        let url: URL = outboxFile(ext: ext)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw MediaError.writeFailed
        }
        return url
    }

    /// A new file name in the outbox (Caches/vow-outbox/<uuid>.<ext>), creating the folder if the system purged it.
    private static func outboxFile(ext: String) -> URL {
        try? FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true, attributes: nil)
        return outbox.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }
}
