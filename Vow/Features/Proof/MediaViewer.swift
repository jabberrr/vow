import AVFoundation
import AVKit
import Observation
import SwiftUI
import UIKit

/// A proof's photo or video, full screen: the photo fitted (pinch or double-tap to zoom), the video in the system
/// player, playing at once and heard even in silent mode. The cached thumbnail stands in while the full file
/// downloads. Black with white chrome, the one place colour isn't `Ink`'s, because it frames photographs. A tap on
/// the photo toggles the chrome, and a swipe down closes. A video keeps its chrome clear of the player, so it never
/// covers the system controls.
struct MediaViewer: View {
    let id: GroupID
    let postID: String

    @Environment(AppStore.self) private var store: AppStore
    @Environment(\.dismiss) private var dismiss: DismissAction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver: Bool

    @State private var thumb: UIImage? = nil
    @State private var photo: UIImage? = nil
    @State private var player: AVPlayer? = nil
    @State private var load: ViewerLoad = .loading
    /// The post or its file doesn't exist (a test reset, a group that has gone): nothing to retry.
    @State private var unavailable: Bool = false
    /// Bumped by Try again, which loads the file again.
    @State private var attempt: Int = 0
    @State private var chromeShown: Bool = true
    @State private var zoomed: Bool = false
    /// Where a swipe that closes the viewer let go, so the picture leaves from there.
    @State private var released: CGSize? = nil
    /// The audio session as it was before a video took it over; put back on close.
    @State private var priorAudio: AudioSessionSetup? = nil
    @GestureState(resetTransaction: Transaction(animation: Anim.standard)) private var drag: CGSize = .zero

    /// A swipe down this far closes the viewer, as does a fling expected to travel `flingDistance`.
    private static let closeDistance: CGFloat = 120
    private static let flingDistance: CGFloat = 400
    /// Under Reduce Motion the picture fades instead of following the finger: fully faded this far down.
    private static let fadeDistance: CGFloat = 300

    init(id: GroupID, postID: String) {
        self.id = id
        self.postID = postID
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            if let shown: PostInfo = post, !unavailable {
                page(shown)
                    .offset(reduceMotion ? CGSize.zero : (released ?? drag))
                    .opacity(fade)
            } else {
                missing
            }
        }
        .gesture(closeDrag, including: zoomed ? .subviews : .all)
        .task(id: attempt) {
            await loadMedia()
        }
        .onChange(of: post == nil) { (_: Bool, gone: Bool) in
            // A reset or a removed group took the post: its video mustn't play on behind the message.
            if gone {
                player?.pause()
            }
        }
        .onDisappear {
            player?.pause()
            restoreAudio()
        }
        .accessibilityAction(.escape, close)
    }

    /// The post, while it is still in the chat: a reset to another epoch takes it out.
    private var post: PostInfo? {
        guard let s: GroupSnapshot = store.snapshots[id] else { return nil }
        return s.posts.first { (p: PostInfo) -> Bool in
            p.id == postID && p.epoch == s.group.epoch && p.media != MediaKind.none
        }
    }

    // MARK: - Page

    @ViewBuilder
    private func page(_ post: PostInfo) -> some View {
        if post.media == .video {
            VStack(spacing: 0) {
                closeRow
                stage(post)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                caption(post)
            }
        } else {
            stage(post)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    photoChrome(post)
                }
        }
    }

    @ViewBuilder
    private func stage(_ post: PostInfo) -> some View {
        switch load {
        case .loading:
            thumbnail(dimmed: false)
                .overlay {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.white)
                }
        case .failed:
            thumbnail(dimmed: true)
                .overlay {
                    failure
                }
        case .ready:
            if let video: AVPlayer = player {
                VideoPlayer(player: video)
            } else if let image: UIImage = photo {
                ZoomablePhoto(image: image,
                              label: MediaText.label(post.media, duration: post.duration),
                              zoomed: $zoomed,
                              onTap: toggleChrome)
            } else {
                thumbnail(dimmed: false)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(dimmed: Bool) -> some View {
        if let image: UIImage = thumb {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .opacity(dimmed ? 0.4 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var failure: some View {
        VStack(spacing: Gap.xs) {
            Text("Couldn't load")
                .font(Fonts.subheadline)
                .foregroundStyle(Color.white.opacity(0.8))
            Button(action: retry) {
                Text("Try again")
                    .font(Fonts.subheadlineSemibold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, Gap.m)
                    .frame(minHeight: Gap.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Gap.gutter)
    }

    private var missing: some View {
        ZStack(alignment: .topLeading) {
            Text("This photo or video isn't available.")
                .font(Fonts.subheadline)
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Gap.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            closeRow
        }
    }

    // MARK: - Chrome

    /// Hidden by a tap or while a swipe is under way; always there for VoiceOver.
    private var chromeVisible: Bool {
        voiceOver || (chromeShown && drag == CGSize.zero && released == nil)
    }

    private func photoChrome(_ post: PostInfo) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .frame(height: 200)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                closeRow
                Spacer(minLength: 0)
                caption(post)
                    .allowsHitTesting(false)
            }
        }
        .opacity(chromeVisible ? 1 : 0)
        .allowsHitTesting(chromeVisible)
        .animation(Anim.fade, value: chromeVisible)
    }

    private var closeRow: some View {
        HStack(spacing: 0) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.16)))
                    .frame(width: Gap.hit, height: Gap.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Close")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Gap.s)
        .padding(.top, Gap.xs)
    }

    /// "Maya · Today 8:14 PM" over the caption.
    private func caption(_ post: PostInfo) -> some View {
        VStack(alignment: .leading, spacing: Gap.xs) {
            Text(byline(post))
                .font(Fonts.footnoteSemibold)
                .foregroundStyle(Color.white.opacity(0.75))
            if !post.text.isEmpty {
                Text(post.text)
                    .font(Fonts.subheadline)
                    .foregroundStyle(Color.white)
                    .lineLimit(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Gap.gutter)
        .padding(.top, Gap.m)
        .padding(.bottom, Gap.xl)
        .accessibilityElement(children: .combine)
    }

    /// The author, then when it was sent in the group's time zone; just the author while it is still sending.
    private func byline(_ post: PostInfo) -> String {
        let author: String
        if post.authorID == store.userID {
            author = "You"
        } else {
            let member: MemberInfo? = store.snapshots[id]?.members.first { (m: MemberInfo) -> Bool in
                m.userID == post.authorID
            }
            author = MemberText.name(member?.displayName ?? "")
        }
        guard let sent: Date = post.serverDate, let group: GroupInfo = store.snapshots[id]?.group else { return author }
        return author + " · " + MediaViewer.when(sent, timeZoneID: group.timeZoneID, now: Date())
    }

    /// "Today 8:14 PM", "Yesterday 11:50 PM", "Oct 19 7:02 AM".
    private static func when(_ date: Date, timeZoneID: String, now: Date) -> String {
        let calendar: Calendar = DayClock.calendar(timeZoneID)
        let time: String = DayText.time(date, timeZoneID: timeZoneID)
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today " + time
        }
        if let yesterday: Date = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday " + time
        }
        return DayText.date(date, timeZoneID: timeZoneID, now: now) + " " + time
    }

    private func toggleChrome() {
        guard !voiceOver else { return }
        chromeShown.toggle()
    }

    // MARK: - Closing

    /// The picture follows the finger; under Reduce Motion it stays put and fades instead.
    private var fade: Double {
        guard reduceMotion else { return 1 }
        let progress: CGFloat = min(1, max(0, (released ?? drag).height) / MediaViewer.fadeDistance)
        return Double(1 - 0.6 * progress)
    }

    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drag) { (value: DragGesture.Value, state: inout CGSize, _: inout Transaction) in
                state = value.translation
            }
            .onEnded { (value: DragGesture.Value) in
                let far: Bool = value.translation.height > MediaViewer.closeDistance
                let flung: Bool = value.predictedEndTranslation.height > MediaViewer.flingDistance
                guard far || flung else { return }
                released = value.translation
                close()
            }
    }

    /// Under Reduce Motion the cover goes without sliding.
    private func close() {
        player?.pause()
        guard reduceMotion else {
            dismiss()
            return
        }
        var still: Transaction = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            dismiss()
        }
    }

    // MARK: - Sound

    /// A video is heard even in silent mode, as people expect of a clip they chose to open: `SoundEngine`'s
    /// ambient session would leave it mute with the ringer off. Photos leave the session alone.
    private func takeAudio() {
        guard priorAudio == nil else { return }
        priorAudio = AudioSessionSetup.playback()
    }

    private func restoreAudio() {
        priorAudio?.restore()
        priorAudio = nil
    }

    // MARK: - Loading

    private func retry() {
        attempt += 1
    }

    /// The thumbnail first (usually cached already), then the full photo or video.
    private func loadMedia() async {
        guard let shown: PostInfo = post else {
            unavailable = true
            return
        }
        load = .loading
        if thumb == nil, let file: URL = await MediaCache.shared.url(for: shown, key: .thumb, in: id) {
            thumb = await MediaImage.decode(file)
        }
        let media: URL? = await MediaCache.shared.url(for: shown, key: .media, in: id)
        // Closed meanwhile: a player started now would play with nothing on screen.
        if Task.isCancelled { return }
        guard let file: URL = media else {
            if MediaCache.shared.isUnavailable(shown, key: .media, in: id) {
                unavailable = true
            } else {
                load = .failed
            }
            return
        }
        if shown.media == .video {
            let video: AVPlayer = AVPlayer(url: file)
            player = video
            load = .ready
            takeAudio()
            video.play()
            return
        }
        let image: UIImage? = await MediaImage.decode(file)
        if Task.isCancelled { return }
        guard let decoded: UIImage = image else {
            load = .failed
            return
        }
        photo = decoded
        load = .ready
    }
}

// MARK: - Zoom

/// The photo fitted to the screen: pinch or double-tap to zoom, drag to look around while zoomed. `zoomed` tells
/// the viewer when a drag should pan rather than close.
private struct ZoomablePhoto: View {
    let image: UIImage
    let label: String
    @Binding var zoomed: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var pan: CGSize = .zero

    private static let maxScale: CGFloat = 4
    private static let doubleTapScale: CGFloat = 2.5

    init(image: UIImage, label: String, zoomed: Binding<Bool>, onTap: @escaping () -> Void) {
        self.image = image
        self.label = label
        self._zoomed = zoomed
        self.onTap = onTap
    }

    var body: some View {
        GeometryReader { (proxy: GeometryProxy) in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(liveScale)
                .offset(bounded(CGSize(width: offset.width + pan.width, height: offset.height + pan.height),
                                scale: liveScale, in: proxy.size))
                .contentShape(Rectangle())
                .gesture(panGesture(in: proxy.size), including: scale > 1 ? .all : .subviews)
                .simultaneousGesture(magnify(in: proxy.size))
                .onTapGesture(count: 2) {
                    toggleZoom()
                }
                .onTapGesture(perform: onTap)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
    }

    private var liveScale: CGFloat {
        min(ZoomablePhoto.maxScale, max(1, scale * pinch))
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { (value: MagnifyGesture.Value, state: inout CGFloat, _: inout Transaction) in
                state = value.magnification
            }
            .onEnded { (value: MagnifyGesture.Value) in
                let next: CGFloat = min(ZoomablePhoto.maxScale, max(1, scale * value.magnification))
                settle(at: next, in: size)
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .updating($pan) { (value: DragGesture.Value, state: inout CGSize, _: inout Transaction) in
                state = value.translation
            }
            .onEnded { (value: DragGesture.Value) in
                let moved: CGSize = CGSize(width: offset.width + value.translation.width,
                                           height: offset.height + value.translation.height)
                offset = bounded(moved, scale: scale, in: size)
            }
    }

    private func toggleZoom() {
        withAnimation(reduceMotion ? nil : Anim.standard) {
            if scale > 1 {
                scale = 1
                offset = .zero
            } else {
                scale = ZoomablePhoto.doubleTapScale
            }
        }
        zoomed = scale > 1
    }

    /// Back to fitted when a pinch ends close to it; otherwise the picture is kept within the screen.
    private func settle(at next: CGFloat, in size: CGSize) {
        if next < 1.05 {
            scale = 1
            offset = .zero
        } else {
            scale = next
            offset = bounded(offset, scale: next, in: size)
        }
        zoomed = scale > 1
    }

    /// An offset that keeps the zoomed picture's edges at or beyond the screen's.
    private func bounded(_ proposed: CGSize, scale s: CGFloat, in size: CGSize) -> CGSize {
        let fitted: CGSize = fittedSize(in: size)
        let maxX: CGFloat = max(0, (fitted.width * s - size.width) / 2)
        let maxY: CGFloat = max(0, (fitted.height * s - size.height) / 2)
        return CGSize(width: min(maxX, max(-maxX, proposed.width)), height: min(maxY, max(-maxY, proposed.height)))
    }

    private func fittedSize(in size: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0, size.height > 0 else { return size }
        let ratio: CGFloat = image.size.width / image.size.height
        if size.width / size.height > ratio {
            return CGSize(width: size.height * ratio, height: size.height)
        }
        return CGSize(width: size.width, height: size.width / ratio)
    }
}

/// How far the viewer has got with the full file.
private enum ViewerLoad: Equatable {
    case loading
    case failed
    case ready
}

/// The shared audio session's category, mode and options, captured so a video's playback can hand them back
/// exactly, whether `SoundEngine` has set its ambient session yet or not. Failures leave the session as it was.
private struct AudioSessionSetup {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions

    /// Switches to playback, which ignores the ringer switch, and returns the setup to restore; nil if the
    /// switch failed. It mixes with other audio, as the ambient session does, so music that is playing isn't
    /// stopped and left paused after the viewer closes. The system default (`.soloAmbient`, before any orb has
    /// set up `SoundEngine`) comes back as `.ambient`: restoring a category that doesn't mix would stop the music.
    static func playback() -> AudioSessionSetup? {
        let session: AVAudioSession = AVAudioSession.sharedInstance()
        let current: AVAudioSession.Category = session.category
        let prior: AudioSessionSetup = AudioSessionSetup(category: current == .soloAmbient ? .ambient : current,
                                                         mode: session.mode,
                                                         options: session.categoryOptions)
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            return prior
        } catch {
            return nil
        }
    }

    func restore() {
        try? AVAudioSession.sharedInstance().setCategory(category, mode: mode, options: options)
    }
}

// MARK: - Preparing (the camera and library pickers)

/// Over a picker while `MediaPrep` works on the pick. It can be cancelled, but not swiped away half done (the
/// picker disables interactive dismissal meanwhile).
struct PreparingOverlay: View {
    let kind: MediaKind
    let onCancel: () -> Void

    @AccessibilityFocusState private var focused: Bool

    init(kind: MediaKind, onCancel: @escaping () -> Void) {
        self.kind = kind
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            Ink.bg.opacity(0.6)
                .ignoresSafeArea()
            card
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            focused = true
        }
    }

    private var card: some View {
        VStack(spacing: Gap.m) {
            ProgressView()
                .tint(Ink.text2)
                .accessibilityHidden(true)
            Text(kind == .video ? "Preparing video…" : "Preparing photo…")
                .font(Fonts.subheadline)
                .foregroundStyle(Ink.text2)
                .multilineTextAlignment(.center)
                .accessibilityFocused($focused)
            PillButton("Cancel", kind: .secondary, compact: true, action: onCancel)
        }
        .padding(Gap.l)
        .background(RoundedRectangle(cornerRadius: Corner.field, style: .continuous).fill(Ink.toast))
        .padding(.horizontal, Gap.xxl)
    }
}

/// Turns a pick into a draft while the picker shows `PreparingOverlay`. Cancel, or the picker closing, abandons
/// the work; `MediaPrep` can't stop half way, so whatever it writes is discarded once it ends.
@MainActor
@Observable
final class ProofPrep {
    /// What is being prepared, for the overlay's words; nil while nothing is.
    private(set) var kind: MediaKind? = nil
    @ObservationIgnored private var task: Task<Void, Never>? = nil

    /// One pick at a time. `ready` receives the draft and owns its files from then on. `failed` runs if `work`
    /// throws, unless the pick was abandoned meanwhile.
    func start(_ kind: MediaKind,
               work: @escaping () async throws -> MediaDraft,
               ready: @escaping (MediaDraft) -> Void,
               failed: @escaping () -> Void) {
        guard task == nil else { return }
        self.kind = kind
        task = Task { @MainActor in
            let draft: MediaDraft? = try? await work()
            let abandoned: Bool = Task.isCancelled
            self.task = nil
            if abandoned {
                if let unwanted: MediaDraft = draft {
                    MediaPrep.discard(unwanted)
                }
                return
            }
            guard let prepared: MediaDraft = draft else {
                self.kind = nil
                failed()
                return
            }
            ready(prepared)
        }
    }

    /// The overlay stays up: the picker is closing.
    func cancel() {
        task?.cancel()
    }
}
