import CloudKit
import Foundation

/// Main-thread mailbox for accepted CloudKit share invitations. The scene delegate delivers
/// metadata (possibly before the AppStore exists); it is buffered until a handler is installed.
@MainActor
enum ShareInbox {
    private static var buffer: [CKShare.Metadata] = []

    static var handler: ((CKShare.Metadata) -> Void)? = nil {
        didSet { flush() }
    }

    static func deliver(_ metadata: CKShare.Metadata) {
        if let h = handler {
            h(metadata)
        } else {
            buffer.append(metadata)
        }
    }

    private static func flush() {
        guard let h = handler, !buffer.isEmpty else { return }
        let pending: [CKShare.Metadata] = buffer
        buffer.removeAll()
        for metadata in pending {
            h(metadata)
        }
    }
}
