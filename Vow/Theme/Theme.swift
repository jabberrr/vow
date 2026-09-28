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

enum Theme {
    static let bg: Color = Color(hex: 0x07060F)
    static let cyan: Color = Color(hex: 0x22D3EE)
    static let purple: Color = Color(hex: 0xA855F7)
    static let pink: Color = Color(hex: 0xFF3DF0)
    static let lime: Color = Color(hex: 0xAEF743)
    static let amber: Color = Color(hex: 0xFFB020)

    /// cyan -> purple -> pink, leading -> trailing
    static let brand: LinearGradient = LinearGradient(
        colors: [Color(hex: 0x22D3EE), Color(hex: 0xA855F7), Color(hex: 0xFF3DF0)],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Hairline rim: white .35 -> cyan .25 -> pink .15 -> white .05, topLeading -> bottomTrailing
    static let rim: LinearGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.35),
            Color(hex: 0x22D3EE, alpha: 0.25),
            Color(hex: 0xFF3DF0, alpha: 0.15),
            Color.white.opacity(0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }

    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }
}
