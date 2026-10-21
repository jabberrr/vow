import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The photo library, as a sheet: one photo or video. PHPicker runs outside the app, so it needs no library
/// permission. The pick is loaded and prepared off the main thread while `PreparingOverlay` covers the picker;
/// once it is a draft, the shell hands it to the proof sheet, which takes over.
struct LibraryPicker: View {
    /// The prepared pick: the shell presents the proof sheet with it.
    let onPicked: (MediaDraft) -> Void

    @Environment(AppStore.self) private var store: AppStore
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var prep: ProofPrep = ProofPrep()

    init(onPicked: @escaping (MediaDraft) -> Void) {
        self.onPicked = onPicked
    }

    var body: some View {
        ZStack {
            LibraryController(onPick: prepare, onCancel: { dismiss() })
            if let kind: MediaKind = prep.kind {
                PreparingOverlay(kind: kind, onCancel: cancel)
            }
        }
        .interactiveDismissDisabled(prep.kind != nil)
        .onDisappear {
            prep.cancel()
        }
    }

    // MARK: - Preparing

    private func prepare(_ item: NSItemProvider) {
        if item.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            prep.start(.video, work: { () async throws -> MediaDraft in
                let copy: URL = try await LibraryPicker.copyVideo(from: item)
                defer { try? FileManager.default.removeItem(at: copy) }
                try Task.checkCancellation()
                return try await MediaPrep.video(at: copy)
            }, ready: handOn, failed: { fail("Couldn't use that video.") })
        } else {
            prep.start(.photo, work: { () async throws -> MediaDraft in
                let image: UIImage = try await LibraryPicker.loadPhoto(from: item)
                try Task.checkCancellation()
                return try await MediaPrep.photo(image)
            }, ready: handOn, failed: { fail("Couldn't use that photo.") })
        }
    }

    /// The picker closes and the proof sheet rises with the draft.
    private func handOn(_ draft: MediaDraft) {
        onPicked(draft)
    }

    private func fail(_ message: String) {
        store.toast = message
        dismiss()
    }

    private func cancel() {
        prep.cancel()
        dismiss()
    }

    // MARK: - Loading

    /// Decoded on the item provider's own queue.
    private static func loadPhoto(from item: NSItemProvider) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { (done: CheckedContinuation<UIImage, Error>) in
            guard item.canLoadObject(ofClass: UIImage.self) else {
                done.resume(throwing: MediaError.unreadable)
                return
            }
            _ = item.loadObject(ofClass: UIImage.self) { (object: NSItemProviderReading?, _: Error?) in
                if let image = object as? UIImage {
                    done.resume(returning: image)
                } else {
                    done.resume(throwing: MediaError.unreadable)
                }
            }
        }
    }

    /// PHPicker deletes its file as soon as this callback returns, so the video is copied (on the provider's queue)
    /// to a temporary file of our own, which the caller deletes once it has been converted.
    private static func copyVideo(from item: NSItemProvider) async throws -> URL {
        return try await withCheckedThrowingContinuation { (done: CheckedContinuation<URL, Error>) in
            _ = item.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { (file: URL?, _: Error?) in
                guard let source: URL = file else {
                    done.resume(throwing: MediaError.unreadable)
                    return
                }
                let ext: String = source.pathExtension.isEmpty ? "mov" : source.pathExtension
                let copy: URL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                do {
                    try FileManager.default.copyItem(at: source, to: copy)
                    done.resume(returning: copy)
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
    }
}

/// `PHPickerViewController` for one photo or video, handed over as the library's current file (no transcoding:
/// `MediaPrep` converts it anyway).
private struct LibraryController: UIViewControllerRepresentable {
    let onPick: (NSItemProvider) -> Void
    let onCancel: () -> Void

    init(onPick: @escaping (NSItemProvider) -> Void, onCancel: @escaping () -> Void) {
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration: PHPickerConfiguration = PHPickerConfiguration()
        configuration.filter = PHPickerFilter.any(of: [.images, .videos])
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker: PHPickerViewController = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: LibraryController

        init(parent: LibraryController) {
            self.parent = parent
        }

        /// Cancel arrives as an empty pick.
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let item: NSItemProvider = results.first?.itemProvider else {
                parent.onCancel()
                return
            }
            parent.onPick(item)
        }
    }
}
