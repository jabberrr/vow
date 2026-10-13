import SwiftUI

/// Names required by the unchanged Orb/ sources. Do not use anywhere else.
enum Palette {
    /// The neon particle colours of the completion burst, appended to the day's c1/c2.
    static let burstExtras: [Color] = [
        Color(hex: 0x22D3EE), Color(hex: 0xFF3DF0), Color(hex: 0xAEF743), Color(hex: 0xFFB020)
    ]
}

/// Names required by the unchanged Orb/ sources. Do not use anywhere else.
enum Motion {
    /// The room-dim gate; OrbView uses it as its scroll-detection window. Equal to Anim.dimGateNanos.
    static let dimGateNanos: UInt64 = 200_000_000
}
