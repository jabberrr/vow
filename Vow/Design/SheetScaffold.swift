import SwiftUI

/// Title (+ subtitle), close button, scrolling content, and an optional footer pinned above the keyboard.
struct SheetScaffold<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    let onClose: () -> Void
    let content: Content
    /// Nil for a sheet without one: then nothing is inset at the bottom or drawn over the content.
    let footer: Footer?

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
        page
            .background(Ink.sheet.ignoresSafeArea())
    }

    /// The footer's opaque backing hides the content scrolling under it, so it is only there with a footer.
    @ViewBuilder
    private var page: some View {
        if let bar: Footer = footer {
            scroll
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bar
                        .padding(.horizontal, Gap.gutter)
                        .padding(.vertical, Gap.m)
                        .background(Ink.sheet)
                }
        } else {
            scroll
        }
    }

    private var scroll: some View {
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

extension SheetScaffold where Footer == EmptyView {
    /// No footer (Settings), so no bottom inset at all. An `EmptyView` footer would still be an inset with an
    /// opaque backing whose size is up to the system, and iOS 26 has been reported to mis-size empty insets.
    init(title: String,
         subtitle: String? = nil,
         onClose: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.content = content()
        self.footer = nil
    }
}
