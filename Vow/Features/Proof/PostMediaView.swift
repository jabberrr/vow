import SwiftUI
import UIKit

/// A proof's photo or video in the chat, at the width it is offered: the thumbnail filling a frame of the media's
/// shape (no taller than `maxHeight`), a play badge with the length for a video, and the upload's progress or
/// failure over it. The caller makes it a button that opens the viewer; only a thumbnail that failed to load takes
/// the tap itself, to try again.
struct PostMediaView: View {
    let post: PostInfo
    let groupID: GroupID
    let maxHeight: CGFloat

    @Environment(AppStore.self) private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var thumb: UIImage?
    @State private var loadFailed: Bool = false
    /// Bumped by a tap on a thumbnail that failed to load, which loads it again.
    @State private var attempt: Int = 0

    /// Decoded thumbnails, so a card scrolled back into view draws at once rather than from a placeholder.
    private static let decoded: NSCache<NSString, UIImage> = PostMediaView.makeCache()
    private static let shape: RoundedRectangle = RoundedRectangle(cornerRadius: Corner.field, style: .continuous)

    init(post: PostInfo, groupID: GroupID, maxHeight: CGFloat) {
        self.post = post
        self.groupID = groupID
        self.maxHeight = maxHeight
        self._thumb = State(initialValue: PostMediaView.decoded.object(forKey: PostMediaView.cacheKey(post.id, in: groupID)))
    }

    var body: some View {
        MediaFrame(aspect: post.aspect ?? 1, maxHeight: maxHeight).callAsFunction {
            ZStack {
                picture
                if post.media == .video, let seconds: Double = post.duration {
                    VideoBadge(seconds: seconds)
                        .padding(Gap.s)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                sendState
            }
        }
        .clipShape(PostMediaView.shape)
        .contentShape(PostMediaView.shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MediaText.label(post.media, duration: post.duration))
        .accessibilityValue(spokenState)
        .accessibilityActions {
            if showsLoadFailure {
                Button("Try again", action: retry)
            }
        }
        .task(id: "\(post.id)-\(attempt)") {
            await loadThumb()
        }
    }

    // MARK: - Picture

    @ViewBuilder
    private var picture: some View {
        if let image: UIImage = thumb {
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else if loadFailed {
            loadFailure
        } else {
            Ink.field
                .overlay {
                    DelayedSpinner()
                }
        }
    }

    private var showsLoadFailure: Bool {
        thumb == nil && loadFailed
    }

    private var loadFailure: some View {
        VStack(spacing: Gap.xs) {
            Image(systemName: "photo")
                .font(.system(size: 20, weight: .regular))
            Text("Couldn't load")
                .font(Fonts.footnote)
        }
        .foregroundStyle(Ink.text3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.field)
        .contentShape(Rectangle())
        .onTapGesture(perform: retry)
    }

    // MARK: - Sending

    /// Your proof while it uploads, or after its upload failed (Retry and Delete sit in the row under it).
    @ViewBuilder
    private var sendState: some View {
        if store.failedPosts.contains(post.id) {
            ZStack {
                Ink.bg.opacity(0.55)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
            .allowsHitTesting(false)
        } else if let progress: Double = store.uploads[post.id] {
            ZStack {
                Color.black.opacity(0.35)
                UploadRing(progress: progress, animated: !reduceMotion)
            }
            .allowsHitTesting(false)
        }
    }

    /// The caption once sent; while sending or failed, where the upload stands.
    private var spokenState: String {
        if store.failedPosts.contains(post.id) {
            return "Not sent"
        }
        if let progress: Double = store.uploads[post.id] {
            return "Sending, \(Int((progress * 100).rounded())) percent"
        }
        return post.text
    }

    // MARK: - Loading

    private func retry() {
        attempt += 1
    }

    private func loadThumb() async {
        let key: NSString = PostMediaView.cacheKey(post.id, in: groupID)
        if let held: UIImage = PostMediaView.decoded.object(forKey: key) {
            thumb = held
            return
        }
        loadFailed = false
        var image: UIImage? = nil
        if let file: URL = await MediaCache.shared.url(for: post, key: .thumb, in: groupID) {
            image = await MediaImage.decode(file)
        }
        // A newer attempt, or the view leaving, has taken over.
        if Task.isCancelled { return }
        guard let loaded: UIImage = image else {
            loadFailed = true
            return
        }
        PostMediaView.decoded.setObject(loaded, forKey: key)
        thumb = loaded
    }

    private static func cacheKey(_ postID: String, in id: GroupID) -> NSString {
        return (id.zoneName + "/" + postID) as NSString
    }

    private static func makeCache() -> NSCache<NSString, UIImage> {
        let cache: NSCache<NSString, UIImage> = NSCache<NSString, UIImage>()
        cache.countLimit = 80
        return cache
    }
}

// MARK: - Shared with the proof sheet and the viewer

/// Lays its content out at the offered width and at the height the media's shape gives it there, kept within
/// `minHeight...maxHeight`: a tall photo can't fill the page, and a panorama can't shrink to a sliver.
struct MediaFrame: Layout {
    let aspect: Double
    let maxHeight: CGFloat
    let minHeight: CGFloat

    init(aspect: Double, maxHeight: CGFloat, minHeight: CGFloat = 120) {
        self.aspect = aspect
        self.maxHeight = maxHeight
        self.minHeight = minHeight
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width: CGFloat = proposal.width ?? maxHeight * ratio
        return CGSize(width: width, height: max(minHeight, min(maxHeight, width / ratio)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }

    /// Width / height, within the range a post can claim.
    private var ratio: CGFloat {
        let shape: Double = aspect.isFinite ? aspect : 1
        return CGFloat(min(max(shape, Records.aspectRange.lowerBound), Records.aspectRange.upperBound))
    }
}

/// Image files decoded off the main actor and ready to draw, so neither scrolling nor opening waits on a JPEG.
enum MediaImage {
    static func decode(_ file: URL) async -> UIImage? {
        let work: Task<UIImage?, Never> = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image: UIImage = UIImage(contentsOfFile: file.path) else { return nil }
            return image.preparingForDisplay() ?? image
        }
        return await work.value
    }
}

/// How a proof's photo or video is named: its VoiceOver label, and the length on a video's badge.
enum MediaText {
    /// "Proof photo", "Proof video, 14 seconds".
    static func label(_ kind: MediaKind, duration: Double?) -> String {
        guard kind == .video else { return "Proof photo" }
        guard let seconds: Double = duration else { return "Proof video" }
        let n: Int = wholeSeconds(seconds)
        return n == 1 ? "Proof video, 1 second" : "Proof video, \(n) seconds"
    }

    /// "0:14".
    static func clock(_ seconds: Double) -> String {
        let n: Int = wholeSeconds(seconds)
        let rest: Int = n % 60
        return "\(n / 60):" + (rest < 10 ? "0\(rest)" : "\(rest)")
    }

    private static func wholeSeconds(_ seconds: Double) -> Int {
        guard seconds.isFinite else { return 0 }
        return max(0, Int(seconds.rounded()))
    }
}

/// A video's length over its picture, for the caller to place at the bottom leading corner.
struct VideoBadge: View {
    let seconds: Double

    init(seconds: Double) {
        self.seconds = seconds
    }

    var body: some View {
        HStack(spacing: Gap.xs) {
            Image(systemName: "play.fill")
                .font(.system(size: 10, weight: .bold))
            Text(MediaText.clock(seconds))
                .font(Fonts.captionBold)
                .monospacedDigit()
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .accessibilityHidden(true)
    }
}

// MARK: - Parts

/// The upload's progress: a white arc on a faint track, on a dark disc.
private struct UploadRing: View {
    let progress: Double
    let animated: Bool

    init(progress: Double, animated: Bool) {
        self.progress = progress
        self.animated = animated
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animated ? Anim.fade : nil, value: progress)
        }
        .frame(width: 36, height: 36)
        .frame(width: 48, height: 48)
        .background(Circle().fill(Color.black.opacity(0.45)))
    }
}

/// A small spinner that shows only once loading has taken a while, so a quick load never flashes one.
private struct DelayedSpinner: View {
    @State private var visible: Bool = false

    private static let delayNanos: UInt64 = 500_000_000

    init() {}

    var body: some View {
        ProgressView()
            .controlSize(.small)
            .tint(Ink.text3)
            .opacity(visible ? 1 : 0)
            .task {
                try? await Task.sleep(nanoseconds: DelayedSpinner.delayNanos)
                if Task.isCancelled { return }
                visible = true
            }
    }
}
