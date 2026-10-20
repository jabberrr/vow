import SwiftUI

/// Root toast: full width at the top of the safe area. Never takes touches (RootView sets that).
struct ToastBanner: View {
    let text: String

    init(text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Fonts.subheadlineSemibold)
            .foregroundStyle(Ink.text)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: Gap.hit)
            .background(Capsule().fill(Ink.toast).shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// One quiet line about a problem, with one way out.
struct InlineBanner: View {
    let systemImage: String
    let text: String
    let actionTitle: String
    let action: () -> Void

    init(systemImage: String, text: String, actionTitle: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Ink.text2)
                .accessibilityHidden(true)
            Text(text)
                .font(Fonts.footnote)
                .foregroundStyle(Ink.text2)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            PillButton(actionTitle, kind: .secondary, compact: true, action: action)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .cardSurface(radius: Corner.banner)
    }
}

enum TagStyle: Equatable {
    case neutral
    case gain
    case milestone
}

struct Tag: View {
    let text: String
    let systemImage: String?
    let style: TagStyle

    init(_ text: String, systemImage: String? = nil, style: TagStyle = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.style = style
    }

    var body: some View {
        HStack(spacing: style == .milestone ? 6 : 4) {
            if let symbol = systemImage {
                symbolView(symbol)
            }
            Text(text)
                .font(style == .milestone ? Fonts.subheadlineSemibold : Fonts.captionBold)
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, style == .milestone ? 13 : 9)
        .frame(minHeight: style == .milestone ? 32 : 24)
        .background(background)
        .accessibilityElement(children: .combine)
    }

    private var textColor: Color {
        switch style {
        case .neutral: return Ink.text2
        case .gain: return Ink.gain
        case .milestone: return Ink.flame
        }
    }

    @ViewBuilder
    private func symbolView(_ symbol: String) -> some View {
        if style == .milestone {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Ink.flameGradient)
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(textColor)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .neutral:
            Capsule().fill(Color.white.opacity(0.09))
        case .gain:
            Capsule().fill(Ink.gain.opacity(0.12))
        case .milestone:
            Capsule()
                .fill(LinearGradient(colors: [Ink.flameMid.opacity(0.22), Ink.flameGold.opacity(0.22)], startPoint: .leading, endPoint: .trailing))
                .overlay(Capsule().strokeBorder(Ink.flameEdge, lineWidth: 1))
        }
    }
}
