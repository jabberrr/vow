import SwiftUI

/// Common sheet layout on Palette.sheet: title (+ optional subtitle) with a close button, then scrolling
/// content at the gutter. The primary button is always the last child of `content`.
struct SheetChrome<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                content
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 20)
            .padding(.bottom, Space.section)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.sheet, ignoresSafeAreaEdges: .all)
        .presentationBackground(Palette.sheet)
        .presentationCornerRadius(Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            titles
            Spacer(minLength: 8)
            CloseButton()
                .padding(.top, -7)
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Typeface.title2)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(Typeface.subheadline)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
