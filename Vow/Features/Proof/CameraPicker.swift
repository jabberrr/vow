import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The camera, as a cover: a photo or a video of up to `MediaPrep.videoLimit` seconds. Access is checked before
/// any camera UI shows, so a refusal gets `CameraAccessView` (and the library) instead of a black screen. Once the
/// capture is a draft, the shell hands it to the proof sheet, which takes over from the cover.
struct CameraPicker: View {
    /// The prepared capture: the shell presents the proof sheet with it.
    let onPicked: (MediaDraft) -> Void
    /// "Choose from library" (access refused, or no camera): the shell presents the library instead.
    let onLibrary: () -> Void

    @Environment(AppStore.self) private var store: AppStore
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var access: CameraAccess = .checking
    @State private var prep: ProofPrep = ProofPrep()

    init(onPicked: @escaping (MediaDraft) -> Void, onLibrary: @escaping () -> Void) {
        self.onPicked = onPicked
        self.onLibrary = onLibrary
    }

    var body: some View {
        ZStack {
            Ink.bg
                .ignoresSafeArea()
            content
            if let kind: MediaKind = prep.kind {
                PreparingOverlay(kind: kind, onCancel: cancel)
            }
        }
        .interactiveDismissDisabled(prep.kind != nil)
        .task {
            await checkAccess()
        }
        .onDisappear {
            prep.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch access {
        case .checking:
            Color.clear
        case .granted:
            CameraController(onPhoto: preparePhoto, onVideo: prepareVideo, onCancel: { dismiss() })
                .ignoresSafeArea()
        case .denied:
            CameraAccessView(onClose: { dismiss() }, onLibrary: chooseLibrary)
        case .unavailable:
            closeOnly
        }
    }

    /// No camera: the library is on its way. Close is there in case it never comes.
    private var closeOnly: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SheetCloseButton(action: { dismiss() })
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Gap.s)
            .padding(.top, Gap.xs)
            Spacer(minLength: 0)
        }
    }

    /// Asks the first time; a refusal (or a restriction) shows the explanation instead.
    private func checkAccess() async {
        guard access == .checking else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            access = .unavailable
            chooseLibrary()
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .granted
        case .notDetermined:
            let allowed: Bool = await AVCaptureDevice.requestAccess(for: .video)
            access = allowed ? .granted : .denied
        case .denied, .restricted:
            access = .denied
        @unknown default:
            access = .denied
        }
    }

    // MARK: - Preparing

    private func preparePhoto(_ image: UIImage) {
        prep.start(.photo, work: { () async throws -> MediaDraft in
            return try await MediaPrep.photo(image)
        }, ready: handOn, failed: { fail("Couldn't use that photo.") })
    }

    /// The recording is the app's own temporary file: it goes once it has been converted, or abandoned.
    private func prepareVideo(_ recording: URL) {
        prep.start(.video, work: { () async throws -> MediaDraft in
            defer { try? FileManager.default.removeItem(at: recording) }
            try Task.checkCancellation()
            return try await MediaPrep.video(at: recording)
        }, ready: handOn, failed: { fail("Couldn't use that video.") })
    }

    /// The cover closes and the proof sheet rises with the draft.
    private func handOn(_ draft: MediaDraft) {
        onPicked(draft)
    }

    private func chooseLibrary() {
        onLibrary()
    }

    private func fail(_ message: String) {
        store.toast = message
        dismiss()
    }

    private func cancel() {
        prep.cancel()
        dismiss()
    }
}

/// Instead of the camera when access is off: how to turn it on, and the library as the way on meanwhile.
struct CameraAccessView: View {
    let onClose: () -> Void
    let onLibrary: () -> Void

    @Environment(\.openURL) private var openURL: OpenURLAction

    init(onClose: @escaping () -> Void, onLibrary: @escaping () -> Void) {
        self.onClose = onClose
        self.onLibrary = onLibrary
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SheetCloseButton(action: onClose)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Gap.s)
            .padding(.top, Gap.xs)
            GeometryReader { (proxy: GeometryProxy) in
                ScrollView(.vertical, showsIndicators: false) {
                    explanation
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(Ink.bg.ignoresSafeArea())
    }

    private var explanation: some View {
        VStack(spacing: 0) {
            Image(systemName: "camera.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Ink.text2)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Ink.field))
                .accessibilityHidden(true)
            Text("Camera access is off")
                .font(Fonts.title2)
                .foregroundStyle(Ink.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Gap.xl)
            Text("Turn it on in Settings to take proof here, or choose from your library.")
                .font(Fonts.subheadline)
                .foregroundStyle(Ink.text2)
                .padding(.top, Gap.s)
            VStack(spacing: 10) {
                PillButton("Open Settings", action: openSettings)
                PillButton("Choose from library", kind: .secondary, action: onLibrary)
            }
            .padding(.top, Gap.section)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Gap.xxl)
        .padding(.vertical, Gap.xl)
    }

    private func openSettings() {
        guard let url: URL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

/// Whether the camera can be shown, worked out before any camera UI appears.
private enum CameraAccess: Equatable {
    case checking
    case granted
    case denied
    /// No camera on this device (the Simulator).
    case unavailable
}

/// `UIImagePickerController` with the camera: photos, and videos cut off at `MediaPrep.videoLimit`.
private struct CameraController: UIViewControllerRepresentable {
    let onPhoto: (UIImage) -> Void
    let onVideo: (URL) -> Void
    let onCancel: () -> Void

    init(onPhoto: @escaping (UIImage) -> Void, onVideo: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        self.onPhoto = onPhoto
        self.onVideo = onVideo
        self.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker: UIImagePickerController = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoMaximumDuration = MediaPrep.videoLimit
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraController

        init(parent: CameraController) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let recording = info[.mediaURL] as? URL {
                parent.onVideo(recording)
            } else if let image = info[.originalImage] as? UIImage {
                parent.onPhoto(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
