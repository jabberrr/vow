import SwiftUI

/// The composer's "+" card: proof for your claim, from the camera or the library, and an excuse for today.
/// A custom card, not a SwiftUI `Menu`, because each row leads to a sheet or a cover and a disabled row says
/// why in place. There is no plain photo row: in this chat a photo is always proof. It takes its own height,
/// and scrolls only when the page can't hold it (large text on a small screen). VoiceOver is held inside it
/// and starts on the first row it can use; escape closes it.
struct ChatPlusMenu: View {
    /// What proof sent now attaches to, or why there is none: "Proof for today's check-in".
    let header: String
    /// There is a claim to attach proof to (`Review.proofDay`).
    let canAddProof: Bool
    /// The device has a camera; without one, "Take photo or video" isn't offered.
    let hasCamera: Bool
    /// Why today can't be excused; nil when it can.
    let excuseNote: String?
    let onTakeProof: () -> Void
    let onPickProof: () -> Void
    let onExcuse: () -> Void
    let onClose: () -> Void

    @AccessibilityFocusState private var focused: PlusRow?

    private static let rowHeight: CGFloat = 50
    /// The symbol column; the divider starts past it (12 + 32 + 12).
    private static let symbolWidth: CGFloat = 32

    init(header: String,
         canAddProof: Bool,
         hasCamera: Bool,
         excuseNote: String?,
         onTakeProof: @escaping () -> Void,
         onPickProof: @escaping () -> Void,
         onExcuse: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.header = header
        self.canAddProof = canAddProof
        self.hasCamera = hasCamera
        self.excuseNote = excuseNote
        self.onTakeProof = onTakeProof
        self.onPickProof = onPickProof
        self.onExcuse = onExcuse
        self.onClose = onClose
    }

    /// The proof rows read the header's reason with their title when they are off.
    private var proofReason: String? {
        canAddProof ? nil : header
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            rows
            ScrollView(.vertical, showsIndicators: false) {
                rows
            }
        }
        .background(card)
        .clipShape(RoundedRectangle(cornerRadius: Corner.field, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Corner.field, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .background(shadow)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .onAppear {
            focused = firstEnabled
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(Fonts.footnote)
                .foregroundStyle(Ink.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Gap.m)
                .padding(.top, 10)
                .padding(.bottom, Gap.xs)
            if hasCamera {
                row(.camera, symbol: "camera.fill", title: "Take photo or video", note: nil, reason: proofReason,
                    action: onTakeProof)
            }
            row(.library, symbol: "photo.on.rectangle", title: "Choose from library", note: nil, reason: proofReason,
                action: onPickProof)
            Hairline(leading: Gap.m + ChatPlusMenu.symbolWidth + Gap.m)
            row(.excuse, symbol: "hand.raised", title: "Excuse for today", note: excuseNote, reason: excuseNote,
                action: onExcuse)
        }
    }

    private var firstEnabled: PlusRow? {
        if canAddProof {
            return hasCamera ? .camera : .library
        }
        return excuseNote == nil ? .excuse : nil
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: Corner.field, style: .continuous)
            .fill(Ink.toast)
    }

    /// Drawn behind the clipped card, like the toast's.
    private var shadow: some View {
        RoundedRectangle(cornerRadius: Corner.field, style: .continuous)
            .fill(Ink.toast)
            .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10)
    }

    /// `reason`: why the row is off (nil when it can be used), merged into its VoiceOver label. `note`: the
    /// reason shown under the title.
    private func row(_ kind: PlusRow, symbol: String, title: String, note: String?, reason: String?,
                     action: @escaping () -> Void) -> some View {
        let enabled: Bool = reason == nil
        return Button(action: action) {
            HStack(spacing: Gap.m) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Ink.text)
                    .frame(width: ChatPlusMenu.symbolWidth)
                    .opacity(enabled ? 1 : 0.35)
                VStack(alignment: .leading, spacing: Gap.xxs) {
                    Text(title)
                        .font(Fonts.body)
                        .foregroundStyle(Ink.text)
                        .opacity(enabled ? 1 : 0.35)
                    if let text: String = note {
                        Text(text)
                            .font(Fonts.footnote)
                            .foregroundStyle(Ink.text3)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Gap.m)
            .padding(.vertical, Gap.s)
            .frame(minHeight: ChatPlusMenu.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(reason.map { (why: String) -> String in title + ". " + why + "." } ?? title)
        .accessibilityFocused($focused, equals: kind)
    }
}

/// The "+" card's rows, for VoiceOver's first focus.
private enum PlusRow: Hashable {
    case camera, library, excuse
}
