import SwiftUI
import UIKit

/// A prepared photo or video, an optional caption, and Send. The proof joins your claim on `Review.proofDay`:
/// today's check-in or excuse, or yesterday's while the group can still vote on it. Send checks that day again;
/// if voting has closed meanwhile the sheet stays up with the reason. Otherwise it closes at once and the upload
/// carries on in the chat. Closed without sending, the draft's files are deleted; once sent, the store owns them.
struct ProofSheet: View {
    let id: GroupID
    let draft: MediaDraft

    @Environment(AppStore.self) private var store: AppStore
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var caption: String = ""
    @State private var preview: UIImage? = nil
    /// The claim as the sheet opened, so the title holds if voting closes while it is up.
    @State private var opened: ProofTarget? = nil
    /// Voting on the claim's day has closed: Send can't go.
    @State private var refused: Bool = false
    @State private var sent: Bool = false
    /// The sheet's height without the keyboard, so the preview doesn't shrink while you type; 0 until measured.
    @State private var sheetHeight: CGFloat = 0

    /// The preview is never taller than this, nor than 45 % of the sheet.
    private static let previewCap: CGFloat = 360

    init(id: GroupID, draft: MediaDraft) {
        self.id = id
        self.draft = draft
    }

    var body: some View {
        let target: ProofTarget? = currentTarget() ?? opened
        SheetScaffold(title: target?.isToday == false ? "Proof for yesterday" : "Proof for today",
                      subtitle: subtitle,
                      onClose: { dismiss() }) {
            form(target: target)
        } footer: {
            PillButton("Send", enabled: !refused, action: send)
        }
        .background {
            sheetMeasure
        }
        .onAppear(perform: open)
        .task {
            preview = await MediaImage.decode(draft.kind == .video ? draft.thumbURL : draft.mediaURL)
        }
        .onChange(of: caption) { (_: String, value: String) in
            guard value.count > Records.postTextLimit else { return }
            caption = String(value.prefix(Records.postTextLimit))
        }
        .onDisappear {
            if !sent {
                MediaPrep.discard(draft)
            }
        }
    }

    /// Your short vow.
    private var subtitle: String? {
        let vow: String = VowFormat.short(store.myMember(id)?.vow ?? "")
        return vow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : vow
    }

    private var sheetMeasure: some View {
        GeometryReader { (proxy: GeometryProxy) in
            Color.clear
                .onAppear {
                    sheetHeight = proxy.size.height
                }
                .onChange(of: proxy.size.height) { (_: CGFloat, height: CGFloat) in
                    sheetHeight = height
                }
        }
        .ignoresSafeArea(.keyboard)
    }

    private var previewHeight: CGFloat {
        sheetHeight > 0 ? min(ProofSheet.previewCap, sheetHeight * 0.45) : ProofSheet.previewCap
    }

    private func form(target: ProofTarget?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            previewBox(maxHeight: previewHeight)
            FieldLabel("Caption")
                .padding(.top, Gap.xl)
            VowTextField("Caption", text: $caption, placeholder: "Add a caption", multiline: true, onReturn: endEditing)
            FieldFooter(note(target))
            if refused {
                FormError("Voting on that day has closed, so this can't be added.")
            }
        }
    }

    /// Fitted, centred on the field colour. A video shows its thumbnail and length; it doesn't play here.
    private func previewBox(maxHeight: CGFloat) -> some View {
        MediaFrame(aspect: draft.aspect, maxHeight: maxHeight).callAsFunction {
            ZStack(alignment: .bottomLeading) {
                Ink.field
                if let image: UIImage = preview {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if draft.kind == .video, let seconds: Double = draft.duration {
                    VideoBadge(seconds: seconds)
                        .padding(Gap.s)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Corner.field, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MediaText.label(draft.kind, duration: draft.duration))
    }

    private func note(_ target: ProofTarget?) -> String {
        let claim: String = target?.isExcuse == true
            ? "Your group sees it on your excuse."
            : "Your group sees it on your check-in."
        guard draft.kind == .video else { return claim }
        return claim + " Videos keep their first \(Int(MediaPrep.videoLimit)) seconds."
    }

    // MARK: - Actions

    private func open() {
        guard opened == nil else { return }
        opened = currentTarget()
        refused = opened == nil
    }

    /// The day is checked again: the sheet may have been up past the end of its voting.
    private func send() {
        guard !sent else { return }
        guard currentTarget() != nil else {
            refused = true
            return
        }
        sent = true
        let store: AppStore = self.store
        let draft: MediaDraft = self.draft
        let text: String = caption
        let group: GroupID = id
        Task { @MainActor in
            await store.sendProof(draft, caption: text, in: group)
        }
        dismiss()
    }

    /// Return closes the keyboard; the caption is one paragraph.
    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// The claim proof sent now would join, as `AppStore.sendProof` will work it out.
    private func currentTarget() -> ProofTarget? {
        let now: Date = Date()
        guard let me: String = store.userID, let s: GroupSnapshot = store.snapshots[id],
              let day: Int = Review.proofDay(for: me, snapshot: s, now: now) else { return nil }
        let isExcuse: Bool
        switch Review.tally(subject: me, day: day, snapshot: s, now: now)?.kind {
        case .some(.excuse):
            isExcuse = true
        case .some(.checkIn), .none:
            isExcuse = false
        }
        return ProofTarget(isToday: day == DayClock.currentDay(s.group, now: now), isExcuse: isExcuse)
    }
}

/// The claim a proof joins: today's or yesterday's, a check-in's or an excuse's.
private struct ProofTarget: Equatable {
    let isToday: Bool
    let isExcuse: Bool
}
