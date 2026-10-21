import SwiftUI

/// Home's foot: one line reserved under the strip on a member's stage, excused or not. Before you check in
/// it offers an excuse. Proof follows the orb quietly: once the check-in's cascade is over, a text button
/// invites it, then the line follows its upload to "Proof sent". It never asks in the moment, never badges
/// and never asks for proof of an excuse. Whatever it shows, the line keeps its 44 pt.
struct StageFoot: View {
    /// What the line shows. StageScreen picks it, since it knows where the cascade is.
    enum Phase: Equatable {
        /// Not checked in or excused yet, also during a hold: "Can't today?".
        case excuse
        /// Excused, or the check-in's cascade is still running: nothing.
        case quiet
        /// Your proof for today is uploading: these posts. The line reads their progress itself.
        case sending([String])
        /// Your proof for today didn't send: the post to send again.
        case notSent(String)
        /// Checked in with no proof yet, or the check-in stands overruled (proof is how minds change).
        case addProof
        case proofSent
    }

    let phase: Phase
    let onExcuse: () -> Void
    let onAddProof: () -> Void
    let onRetry: (String) -> Void
    let onShowChat: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    init(phase: Phase,
         onExcuse: @escaping () -> Void,
         onAddProof: @escaping () -> Void,
         onRetry: @escaping (String) -> Void,
         onShowChat: @escaping () -> Void) {
        self.phase = phase
        self.onExcuse = onExcuse
        self.onAddProof = onAddProof
        self.onRetry = onRetry
        self.onShowChat = onShowChat
    }

    var body: some View {
        ZStack {
            content
        }
        .frame(maxWidth: .infinity, minHeight: Gap.hit)
        .animation(Anim.fade, value: phase)
    }

    /// Each phrasing fades in with a small rise and fades out in place.
    @ViewBuilder
    private var content: some View {
        switch phase {
        case .excuse:
            excuseButton
                .transition(transition)
        case .quiet:
            EmptyView()
        case .sending(let postIDs):
            SendingProof(postIDs: postIDs)
                .transition(transition)
        case .notSent(let postID):
            notSent(postID)
                .transition(transition)
        case .addProof:
            addProofButton
                .transition(transition)
        case .proofSent:
            proofSentButton
                .transition(transition)
        }
    }

    private var transition: AnyTransition {
        if reduceMotion {
            return AnyTransition.opacity
        }
        return AnyTransition.asymmetric(insertion: AnyTransition.opacity.combined(with: .offset(y: 4)),
                                        removal: AnyTransition.opacity)
    }

    // MARK: - Before the check-in

    private var excuseButton: some View {
        Button(action: onExcuse) {
            Text("Can't today?")
                .font(Fonts.subheadlineMedium)
                .foregroundStyle(Ink.text3)
                .modifier(FootTarget())
        }
        .buttonStyle(PressStyle())
        .accessibilityHint("Send an excuse instead of checking in")
        .accessibilityShowsLargeContentViewer()
    }

    // MARK: - Proof

    /// Brighter than the quiet phrasings around it, so it reads as the invitation, but not a pill.
    private var addProofButton: some View {
        Button(action: onAddProof) {
            HStack(spacing: Gap.s) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Add proof")
                    .font(Fonts.subheadlineSemibold)
            }
            .foregroundStyle(Ink.text)
            .modifier(FootTarget())
        }
        .buttonStyle(PressStyle())
        .accessibilityShowsLargeContentViewer()
    }

    /// One element for VoiceOver: "Proof not sent", and activating it sends the proof again.
    private func notSent(_ postID: String) -> some View {
        HStack(spacing: Gap.xs) {
            Text("Proof not sent ·")
                .font(Fonts.subheadlineMedium)
                .foregroundStyle(Ink.text2)
            Button {
                onRetry(postID)
            } label: {
                Text("Retry")
                    .font(Fonts.subheadlineSemibold)
                    .foregroundStyle(Ink.text)
                    .frame(minWidth: Gap.hit, minHeight: Gap.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Proof not sent")
        .accessibilityHint("Sends it again")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onRetry(postID)
        }
    }

    private var proofSentButton: some View {
        Button(action: onShowChat) {
            HStack(spacing: Gap.s) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Proof sent")
                    .font(Fonts.subheadlineMedium)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Ink.text2)
            .modifier(FootTarget())
        }
        .buttonStyle(PressStyle())
        .accessibilityHint("Opens Chat")
        .accessibilityShowsLargeContentViewer()
    }
}

/// "Sending proof", with a ring that follows the least advanced upload. It reads the progress from the store
/// itself, so each step of an upload redraws this line alone: Home's stage, which runs a Settlement pass per
/// body, never observes `uploads`.
private struct SendingProof: View {
    let postIDs: [String]

    @Environment(AppStore.self) private var store: AppStore

    private static let ringSize: CGFloat = 16
    private static let ringLine: CGFloat = 2.5
    /// A sliver of the ring shows from the start, so a slow upload never looks stalled at nothing.
    private static let ringMinimum: Double = 0.04

    init(postIDs: [String]) {
        self.postIDs = postIDs
    }

    var body: some View {
        let progress: Double = least
        return HStack(spacing: Gap.s) {
            ring(progress)
            Text("Sending proof")
                .font(Fonts.subheadlineMedium)
                .foregroundStyle(Ink.text2)
        }
        .frame(minHeight: Gap.hit)
        .animation(Anim.fade, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sending proof")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }

    /// 0...1. A post the store isn't tracking yet counts as not started.
    private var least: Double {
        let uploads: [String: Double] = store.uploads
        var progress: Double = 1
        for postID in postIDs {
            progress = min(progress, uploads[postID] ?? 0)
        }
        return progress
    }

    private func ring(_ progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Ink.field, lineWidth: SendingProof.ringLine)
            Circle()
                .trim(from: 0, to: max(progress, SendingProof.ringMinimum))
                .stroke(Ink.text2, style: StrokeStyle(lineWidth: SendingProof.ringLine, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: SendingProof.ringSize - SendingProof.ringLine, height: SendingProof.ringSize - SendingProof.ringLine)
        .padding(SendingProof.ringLine / 2)
    }
}

/// A text button's 44 pt target, a little wider than its words.
private struct FootTarget: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Gap.l)
            .frame(minHeight: Gap.hit)
            .contentShape(Rectangle())
    }
}
