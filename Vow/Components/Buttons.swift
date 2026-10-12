import SwiftUI

/// Icon + title row shared by the capsule labels.
private struct CapsuleLabelRow: View {
    let title: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let name = systemImage {
                Image(systemName: name)
                    .font(.system(size: 15, weight: .semibold))
            }
            Text(title)
                .font(Typeface.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 10)
    }
}

/// White capsule label. Enabled: Palette.text fill, Palette.onLight content. Disabled: Palette.overlay fill,
/// Palette.text3 content. Busy: content hidden, spinner centred on top.
/// Shared by PrimaryButton, ShareLink and TestBar.
struct PrimaryLabel: View {
    let title: String
    let systemImage: String?
    let busy: Bool
    let enabled: Bool

    init(title: String, systemImage: String? = nil, busy: Bool = false, enabled: Bool = true) {
        self.title = title
        self.systemImage = systemImage
        self.busy = busy
        self.enabled = enabled
    }

    private var fill: Color {
        enabled ? Palette.text : Palette.overlay
    }

    private var contentColor: Color {
        enabled ? Palette.onLight : Palette.text3
    }

    private var spokenValue: String {
        busy ? "In progress" : ""
    }

    var body: some View {
        ZStack {
            CapsuleLabelRow(title: title, systemImage: systemImage)
                .foregroundStyle(contentColor)
                .opacity(busy ? 0 : 1)
            if busy {
                ProgressView()
                    .tint(Palette.onLight)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Space.buttonHeight)
        .background(Capsule().fill(fill))
        .contentShape(Capsule())
        .animation(Motion.fade, value: busy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spokenValue)
    }
}

/// The one primary action of a screen or sheet. Disabled while `busy` or not `enabled`.
struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, busy: Bool = false, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.busy = busy
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button {
            action()
        } label: {
            PrimaryLabel(title: title, systemImage: systemImage, busy: busy, enabled: enabled)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled || busy)
        .animation(Motion.fade, value: enabled)
        .animation(Motion.fade, value: title)
    }
}

/// Palette.raised capsule, 1pt Palette.hairline stroke, Palette.text content, same layout as PrimaryLabel.
struct SecondaryLabel: View {
    let title: String
    let systemImage: String?

    init(title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        CapsuleLabelRow(title: title, systemImage: systemImage)
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: Space.buttonHeight)
            .background(Capsule().fill(Palette.raised))
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            .contentShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
    }
}

/// Neutral capsule action. Fades to 0.4 when not `enabled`; label swaps (Copy link / Copied) crossfade.
struct SecondaryButton: View {
    let title: String
    let systemImage: String?
    let enabled: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button {
            action()
        } label: {
            SecondaryLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .animation(Motion.fade, value: enabled)
        .animation(Motion.fade, value: title)
    }
}

/// Sheet close: 30pt Palette.overlay circle with an xmark, inside a 44x44 tappable frame. Calls dismiss().
struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.text2)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.overlay))
                .frame(width: Space.hitTarget, height: Space.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Close")
    }
}
