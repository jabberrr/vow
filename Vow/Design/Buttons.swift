import SwiftUI

enum PillKind: Equatable {
    case primary
    case secondary
}

/// The visual of every pill button (also used as a ShareLink label).
struct PillLabel: View {
    let title: String
    let systemImage: String?
    let kind: PillKind
    let busy: Bool
    let compact: Bool

    init(_ title: String, systemImage: String? = nil, kind: PillKind = .primary, busy: Bool = false, compact: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.busy = busy
        self.compact = compact
    }

    private var fill: Color {
        kind == .primary ? Ink.primary : Ink.field
    }

    private var ink: Color {
        kind == .primary ? Ink.onPrimary : Ink.text
    }

    var body: some View {
        ZStack {
            content
                .opacity(busy ? 0 : 1)
            if busy {
                ProgressView()
                    .tint(ink)
            }
        }
        .font(compact ? Fonts.subheadlineSemibold : Fonts.headline)
        .foregroundStyle(ink)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, compact ? 18 : 20)
        .frame(maxWidth: compact ? nil : CGFloat.infinity)
        .frame(minHeight: compact ? 40 : Gap.control)
        .background(Capsule().fill(fill))
        .contentShape(Capsule())
    }

    private var content: some View {
        HStack(spacing: Gap.s) {
            if let symbol = systemImage {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 15 : 17, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
        }
    }
}

struct PillButton: View {
    let title: String
    let systemImage: String?
    let kind: PillKind
    let busy: Bool
    let enabled: Bool
    let compact: Bool
    let action: () -> Void

    init(_ title: String,
         systemImage: String? = nil,
         kind: PillKind = .primary,
         busy: Bool = false,
         enabled: Bool = true,
         compact: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.busy = busy
        self.enabled = enabled
        self.compact = compact
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            PillLabel(title, systemImage: systemImage, kind: kind, busy: busy, compact: compact)
                .padding(.vertical, compact ? 2 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled || busy)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(title)
    }
}

/// 30 pt close disc in a 44 pt target.
struct SheetCloseButton: View {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Ink.text2)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Ink.field))
                .frame(width: Gap.hit, height: Gap.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Close")
    }
}

/// 36 pt icon disc in a 44 pt target (label of the stage's … Menu).
struct CircleIconLabel: View {
    let systemImage: String

    init(systemImage: String) {
        self.systemImage = systemImage
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Ink.text)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Ink.field))
            .frame(width: Gap.hit, height: Gap.hit)
            .contentShape(Rectangle())
    }
}

/// Small capsule button inside a field (Copy, Refresh). 36 pt visual, 44 pt target.
struct FieldAccessoryButton: View {
    let title: String
    let systemImage: String
    let enabled: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(Fonts.subheadlineSemibold)
            }
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(Capsule().fill(Ink.chip))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
