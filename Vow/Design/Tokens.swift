import SwiftUI

extension Color {
    /// 0xRRGGBB in sRGB.
    init(hex: UInt32, alpha: Double = 1) {
        let r: Double = Double((hex >> 16) & 0xFF) / 255.0
        let g: Double = Double((hex >> 8) & 0xFF) / 255.0
        let b: Double = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// Colour roles (dark only). Chrome is neutral; colour always means something:
/// flame = streak, gain/loss = points, the day's orb colours = kept today.
enum Ink {
    static let bg: Color = Color(hex: 0x08090E)
    static let sheet: Color = Color(hex: 0x0F1118)
    static let card: Color = Color(hex: 0x12141C)
    static let field: Color = Color(hex: 0x1A1D27)
    static let chip: Color = Color(hex: 0x2B2F3C)
    static let pressed: Color = Color(hex: 0x1F2330)
    static let avatar: Color = Color(hex: 0x2E3240)
    static let unlit: Color = Color(hex: 0x1A1D28)
    static let missed: Color = Color(hex: 0x2A1A20)
    static let toast: Color = Color(hex: 0x262A36)
    static let hairline: Color = Color.white.opacity(0.07)
    static let text: Color = Color(hex: 0xF4F5F8)
    static let text2: Color = Color(hex: 0xA6ABBD)
    static let text3: Color = Color(hex: 0x80869A)
    static let primary: Color = Color(hex: 0xF4F5F8)
    static let onPrimary: Color = Color(hex: 0x08090E)
    static let flame: Color = Color(hex: 0xFF9F2E)
    static let flameTop: Color = Color(hex: 0xFFD45C)
    static let flameMid: Color = Color(hex: 0xFF8A1F)
    static let flameBottom: Color = Color(hex: 0xFF4F1A)
    static let flameGold: Color = Color(hex: 0xFFC24A)
    static let gain: Color = Color(hex: 0x4ADE9B)
    static let loss: Color = Color(hex: 0xFF7066)

    /// Flame icon fill, top to bottom.
    static var flameGradient: LinearGradient {
        LinearGradient(colors: [Ink.flameTop, Ink.flameMid, Ink.flameBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Next-milestone bar fill, leading to trailing.
    static var milestoneGradient: LinearGradient {
        LinearGradient(colors: [Ink.flameMid, Ink.flameGold], startPoint: .leading, endPoint: .trailing)
    }

    /// Colour for the VIEWER's own points: > 0 gain, < 0 loss, 0 (after 2-decimal rounding) text2.
    static func points(_ value: Double) -> Color {
        let rounded: Double = (value * 100).rounded() / 100
        if rounded > 0 {
            return Ink.gain
        }
        if rounded < 0 {
            return Ink.loss
        }
        return Ink.text2
    }
}

/// Type scale. Dynamic Type text styles; SF Pro Rounded only for numbers.
enum Fonts {
    static let title: Font = Font.system(.title, design: .default, weight: .bold)
    static let title2: Font = Font.system(.title2, design: .default, weight: .bold)
    static let vow: Font = Font.system(.title2, design: .default, weight: .semibold)
    static let section: Font = Font.system(.title3, design: .default, weight: .bold)
    static let headline: Font = Font.headline
    static let body: Font = Font.body
    static let callout: Font = Font.callout
    static let subheadline: Font = Font.subheadline
    static let subheadlineMedium: Font = Font.subheadline.weight(.medium)
    static let subheadlineSemibold: Font = Font.subheadline.weight(.semibold)
    static let footnote: Font = Font.footnote
    static let footnoteMedium: Font = Font.footnote.weight(.medium)
    static let footnoteSemibold: Font = Font.footnote.weight(.semibold)
    static let caption: Font = Font.caption.weight(.medium)
    static let captionBold: Font = Font.caption.weight(.bold)
    /// "Total balance" / "Yesterday" label in the Menu button.
    static let caption2Semibold: Font = Font.caption2.weight(.semibold)
    static let mono: Font = Font.system(.subheadline, design: .monospaced, weight: .regular)
    static let numberSmall: Font = Font.system(.subheadline, design: .rounded, weight: .bold)
    static let numberMedium: Font = Font.system(.title3, design: .rounded, weight: .heavy)
    static let stat: Font = Font.system(.title2, design: .rounded, weight: .heavy)
    static let pill: Font = Font.system(.headline, design: .rounded, weight: .heavy)
    /// Launch screen only (fixed size).
    static let wordmark: Font = Font.system(size: 40, weight: .heavy, design: .rounded)
}

/// 4-pt grid and fixed control sizes.
enum Gap {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let section: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let huge: CGFloat = 48
    static let gutter: CGFloat = 20
    static let barInset: CGFloat = 16
    static let hit: CGFloat = 44
    static let control: CGFloat = 52
    static let dock: CGFloat = 60
    static let orbSlot: CGFloat = 220
}

/// Corner radii (always .continuous). Pills, chips and the dock are Capsules.
enum Corner {
    static let card: CGFloat = 22
    static let banner: CGFloat = 18
    static let field: CGFloat = 14
    static let sheet: CGFloat = 28
}

/// Curves and beat timings. `dimGateNanos` must equal the OrbBridge copy (OrbView reads that one).
enum Anim {
    static let press: Animation = Animation.easeOut(duration: 0.12)
    static let fade: Animation = Animation.easeInOut(duration: 0.25)
    static let standard: Animation = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let reward: Animation = Animation.spring(response: 0.42, dampingFraction: 0.62)
    static let flareUp: Animation = Animation.spring(response: 0.22, dampingFraction: 0.5)
    static let flareDown: Animation = Animation.spring(response: 0.5, dampingFraction: 0.7)
    static let pulse: Animation = Animation.spring(response: 0.3, dampingFraction: 0.5)
    static let light: Animation = Animation.easeInOut(duration: 0.35)
    static let switchVow: Animation = Animation.easeInOut(duration: 0.28)
    static let screen: Animation = Animation.easeInOut(duration: 0.35)
    static let toast: Animation = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let dimIn: Animation = Animation.easeOut(duration: 0.3)
    static let dimOut: Animation = Animation.easeInOut(duration: 0.5)
    static let lightsUp: Animation = Animation.easeOut(duration: 0.25)

    static let dimmedOpacity: Double = 0.12

    static let dimGateNanos: UInt64 = 200_000_000
    static let settleNanos: UInt64 = 120_000_000
    static let rewardNanos: UInt64 = 250_000_000
    static let socialNanos: UInt64 = 450_000_000
    static let milestoneNanos: UInt64 = 700_000_000
    static let nextNanos: UInt64 = 2_000_000_000
    static let offerNanos: UInt64 = 2_300_000_000
    static let hintNanos: UInt64 = 1_200_000_000
    static let toastNanos: UInt64 = 2_200_000_000
    static let revealNanos: UInt64 = 2_500_000_000
    static let focusNanos: UInt64 = 350_000_000
    static let flareHoldNanos: UInt64 = 180_000_000
}

/// Stage spacing. Compact on short screens (safe-area height < 700 pt, e.g. iPhone SE 375×667),
/// so that who kept today, names included, stays above the dock at default text size.
struct StageMetrics: Equatable {
    let compact: Bool
    /// Vertical padding of the pinned global bar (bar row is 44).
    let barPadding: CGFloat
    let vowTop: CGFloat
    let orbTop: CGFloat
    let streakTop: CGFloat
    let captionTop: CGFloat
    /// Fixed gap between the caption and the member strip. Regular: the milestone tag lives inside it
    /// for the session. Compact: the tag covers this gap plus the strip label for 3 s, then the label returns.
    let tagGap: CGFloat
    let tagOffset: CGFloat
    let stripRowTop: CGFloat
    let stripCell: CGFloat
    let detailsTop: CGFloat
    let testBarHeight: CGFloat
    /// Height of the fade above the dock band.
    let dockFade: CGFloat

    static let regular: StageMetrics = StageMetrics(compact: false, barPadding: 4, vowTop: 14, orbTop: 18,
                                                    streakTop: 8, captionTop: 8, tagGap: 44, tagOffset: 6,
                                                    stripRowTop: 12, stripCell: 56, detailsTop: 40,
                                                    testBarHeight: 56, dockFade: 16)
    static let compactPreset: StageMetrics = StageMetrics(compact: true, barPadding: 2, vowTop: 8, orbTop: 8,
                                                    streakTop: 2, captionTop: 6, tagGap: 16, tagOffset: 0,
                                                    stripRowTop: 8, stripCell: 52, detailsTop: 32,
                                                    testBarHeight: 48, dockFade: 8)

    /// `height` = the window's safe-area height (MainView's GeometryReader).
    static func forHeight(_ height: CGFloat) -> StageMetrics {
        return height < 700 ? StageMetrics.compactPreset : StageMetrics.regular
    }
}
