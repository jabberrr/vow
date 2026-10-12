import SwiftUI

extension Color {
    /// 0xRRGGBB
    init(hex: UInt32, alpha: Double = 1) {
        let r: Double = Double((hex >> 16) & 0xFF) / 255.0
        let g: Double = Double((hex >> 8) & 0xFF) / 255.0
        let b: Double = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// Colour tokens. Greyscale chrome; colour only means something (accent = your turn, kept, loss, warn).
enum Palette {
    static let bg: Color = Color(hex: 0x0B0B0E)
    static let sheet: Color = Color(hex: 0x131317)
    static let surface: Color = Color(hex: 0x151519)
    static let raised: Color = Color(hex: 0x1D1D23)
    static let overlay: Color = Color(hex: 0x2A2A31)
    static let thumb: Color = Color(hex: 0x34343C)
    static let dormant: Color = Color(hex: 0x17171C)
    static let hairline: Color = Color.white.opacity(0.07)
    static let divider: Color = Color.white.opacity(0.08)
    static let text: Color = Color(hex: 0xF4F4F6)
    static let text2: Color = Color(hex: 0xABABB5)
    static let text3: Color = Color(hex: 0x85858F)
    static let accent: Color = Color(hex: 0x8C95FF)
    static let kept: Color = Color(hex: 0x3DD68C)
    static let loss: Color = Color(hex: 0xFF6B61)
    static let warn: Color = Color(hex: 0xF2B544)
    static let onLight: Color = Color(hex: 0x0B0B0E)
    /// The neon particle colours, kept for the burst only. Appended to the day's c1/c2.
    static let burstExtras: [Color] = [
        Color(hex: 0x22D3EE), Color(hex: 0xFF3DF0), Color(hex: 0xAEF743), Color(hex: 0xFFB020)
    ]

    /// Colour for the VIEWER's own points: > 0 kept, < 0 loss, 0 (after 2-decimal rounding) `zero`.
    static func points(_ value: Double, zero: Color = Palette.text2) -> Color {
        let rounded: Double = (value * 100).rounded() / 100
        if rounded > 0 { return Palette.kept }
        if rounded < 0 { return Palette.loss }
        return zero
    }
}

/// Type tokens. SF Pro text styles (Dynamic Type); SF Rounded only for numerals and the wordmark.
enum Typeface {
    /// 28: group name, onboarding headline
    static let title: Font = Font.title.weight(.bold)
    /// 22: sheet titles, phase titles
    static let title2: Font = Font.title2.weight(.bold)
    /// 20: vow line, empty/join titles
    static let title3: Font = Font.title3.weight(.semibold)
    /// 17 semibold: row titles, buttons
    static let headline: Font = Font.headline
    /// 17: fields, toggle rows
    static let body: Font = Font.body
    /// 15
    static let subheadline: Font = Font.subheadline
    static let subheadlineMedium: Font = Font.subheadline.weight(.medium)
    static let subheadlineSemibold: Font = Font.subheadline.weight(.semibold)
    /// 13
    static let footnote: Font = Font.footnote
    static let footnoteSemibold: Font = Font.footnote.weight(.semibold)
    /// 12: Chip
    static let caption: Font = Font.caption.weight(.semibold)
    /// Invite URL only.
    static let mono: Font = Font.subheadline.monospaced()
    /// Home "Vow"
    static let wordmark: Font = Font.system(size: 28, weight: .bold, design: .rounded)
    /// Loading "Vow"
    static let wordmarkLarge: Font = Font.system(size: 34, weight: .bold, design: .rounded)
    /// Stat numbers
    static let stat: Font = Font.system(.title2, design: .rounded, weight: .semibold)
    static let statUnit: Font = Font.footnote.weight(.medium)
    static let heroUnit: Font = Font.system(.title2, design: .rounded, weight: .medium)
}

/// 4-pt spacing grid and fixed control sizes.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let section: CGFloat = 32
    static let huge: CGFloat = 40
    static let gutter: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let rowMinHeight: CGFloat = 56
    static let fieldHeight: CGFloat = 52
    static let buttonHeight: CGFloat = 52
    static let hitTarget: CGFloat = 44
}

/// Corner radii (always `.continuous`). Buttons, segments and the toast pill are capsules.
enum Radius {
    static let card: CGFloat = 22
    static let field: CGFloat = 14
    static let chip: CGFloat = 6
    static let sheet: CGFloat = 28
}

/// Animation curves and delays.
enum Motion {
    /// Button / row press.
    static let press: Animation = .easeOut(duration: 0.12)
    /// Label swaps, enable/disable, hint flash, inline title.
    static let fade: Animation = .easeInOut(duration: 0.25)
    /// Segment thumb.
    static let standard: Animation = .spring(response: 0.35, dampingFraction: 0.86)
    /// Base of the reward spring.
    static let emphasis: Animation = .spring(response: 0.42, dampingFraction: 0.62)
    /// Streak roll, today's bead fill (lands after the lights are up).
    static let reward: Animation = Motion.emphasis.delay(0.25)
    /// `reward` under Reduce Motion.
    static let rewardFade: Animation = Animation.easeInOut(duration: 0.25).delay(0.25)
    /// RootView screen swaps.
    static let screen: Animation = .easeInOut(duration: 0.35)
    /// Toast in/out.
    static let toast: Animation = .spring(response: 0.4, dampingFraction: 0.85)
    /// Room dims (the state is gated by `dimGateNanos`; no animation delay).
    static let dimIn: Animation = .easeOut(duration: 0.3)
    /// Lights back after an early release.
    static let dimOut: Animation = .easeInOut(duration: 0.5)
    /// Lights back at the seal.
    static let lightsUp: Animation = .easeOut(duration: 0.25)

    static let toastNanos: UInt64 = 2_200_000_000
    static let dimGateNanos: UInt64 = 200_000_000
    static let rewardDelayNanos: UInt64 = 250_000_000
    static let hintNanos: UInt64 = 600_000_000
    static let autoFocusNanos: UInt64 = 350_000_000
}
