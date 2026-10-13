import SwiftUI

/// Title (+ subtitle), close button, scrolling content, and a footer pinned above the keyboard.
struct SheetScaffold<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    let onClose: () -> Void
    let content: Content
    let footer: Footer

    init(title: String,
         subtitle: String? = nil,
         onClose: @escaping () -> Void,
         @ViewBuilder content: () -> Content,
         @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                content
                    .padding(.top, 22)
            }
            .padding(.horizontal, Gap.gutter)
            .padding(.top, Gap.xl)
            .padding(.bottom, Gap.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
                .padding(.horizontal, Gap.gutter)
                .padding(.vertical, Gap.m)
                .background(Ink.sheet)
        }
        .background(Ink.sheet.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Gap.m) {
            VStack(alignment: .leading, spacing: Gap.xs) {
                Text(title)
                    .font(Fonts.title2)
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let line = subtitle {
                    Text(line)
                        .font(Fonts.subheadline)
                        .foregroundStyle(Ink.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SheetCloseButton(action: onClose)
                .padding(.top, -8)
                .padding(.trailing, -8)
        }
    }
}
