import SwiftUI

/// Floating message pill: one or two centred lines on Palette.overlay with a hairline and a soft shadow.
/// No icon (the store's toast is an untyped string).
struct Toast: View {
    let text: String

    init(text: String) {
        self.text = text
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    var body: some View {
        Text(text)
            .font(Typeface.subheadlineMedium)
            .foregroundStyle(Palette.text)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(fill)
            .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private var fill: some View {
        shape
            .fill(Palette.overlay)
            .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10)
    }
}
