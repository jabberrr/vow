import SwiftUI

/// Gradient capsule label (black text on Theme.brand). Shared by buttons and ShareLink.
struct PrimaryLabel: View {
    let title: String
    var busy: Bool = false

    var body: some View {
        ZStack {
            Text(title)
                .font(Theme.display(17, .bold))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(busy ? 0 : 1)
            if busy {
                ProgressView()
                    .tint(Color.black)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Capsule().fill(Theme.brand))
        .contentShape(Capsule())
    }
}

/// Glass capsule label (white text).
struct SecondaryLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let name = systemImage {
                Image(systemName: name)
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(title)
                .font(Theme.display(16, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.white.opacity(0.9))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.75))
        .contentShape(Capsule())
    }
}

struct PrimaryButton: View {
    let title: String
    var busy: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PrimaryLabel(title: title, busy: busy)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
        .opacity(enabled ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SecondaryLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

/// Small uppercase mono capsule.
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(10, .semibold))
            .tracking(1.0)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 0.75))
    }
}

struct StatusBadge: View {
    let status: MemberStatus

    static func color(for status: MemberStatus) -> Color {
        switch status {
        case .checkedIn: return Theme.lime
        case .missed: return Theme.pink
        case .notYet: return Color.white.opacity(0.5)
        case .yourMove: return Theme.cyan
        }
    }

    var body: some View {
        Badge(text: status.label, color: StatusBadge.color(for: status))
    }
}

struct StakeChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    private var rimStyle: AnyShapeStyle {
        selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.white.opacity(0.15))
    }

    private var fillColor: Color {
        selected ? Theme.purple.opacity(0.22) : Color.white.opacity(0.05)
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.mono(14, .semibold))
                .foregroundStyle(Color.white.opacity(selected ? 1.0 : 0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(fillColor))
                .overlay(Capsule().strokeBorder(rimStyle, lineWidth: selected ? 1.25 : 0.75))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: selected)
    }
}

/// Single-line text field in a glass card.
struct GlassField: View {
    let placeholder: String
    @Binding var text: String
    var font: Font = Theme.display(18, .semibold)
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder).foregroundStyle(Color.white.opacity(0.35))
        )
        .font(font)
        .foregroundStyle(Color.white)
        .submitLabel(.done)
        .textInputAutocapitalization(capitalization)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16, radius: 18)
    }
}

/// Eyebrow title + content, used for form sections.
struct FieldSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .eyebrow()
            content
        }
    }
}
