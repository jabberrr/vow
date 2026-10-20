import SwiftUI

/// Who kept today, at the moment of action: "2 of 5 kept today" over a row of faces lit in the day's
/// colours (you: lit or ringed). Only the people in the group: inviting lives on the Group page. Wraps
/// into rows instead of scrolling, so nobody is hidden.
struct MemberStrip: View {
    let theme: DailyTheme
    let standings: [MemberStanding]
    let viewerID: String
    /// Your sphere and your place in the count light at the social beat, not at the seal.
    let viewerLit: Bool
    let atRisk: Bool
    let cell: CGFloat
    let rowTop: CGFloat
    let onMember: (String) -> Void

    init(theme: DailyTheme,
         standings: [MemberStanding],
         viewerID: String,
         viewerLit: Bool,
         atRisk: Bool,
         cell: CGFloat,
         rowTop: CGFloat,
         onMember: @escaping (String) -> Void) {
        self.theme = theme
        self.standings = standings
        self.viewerID = viewerID
        self.viewerLit = viewerLit
        self.atRisk = atRisk
        self.cell = cell
        self.rowTop = rowTop
        self.onMember = onMember
    }

    /// One face in the strip.
    struct Face: Identifiable {
        let id: String
        let name: String
        let initial: String
        let state: SphereState
        let isYou: Bool
    }

    private static let sphereSize: CGFloat = 40
    private static let spacing: CGFloat = 4

    var body: some View {
        let faces: [Face] = makeFaces()
        VStack(spacing: 0) {
            label
            cells(faces)
                .padding(.top, rowTop)
        }
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: - Label

    private var keptCount: Int {
        let others: [MemberStanding] = standings.filter { (s: MemberStanding) -> Bool in
            s.userID != viewerID
        }
        let hasViewer: Bool = others.count != standings.count
        return Digest.keptCount(others) + (hasViewer && viewerLit ? 1 : 0)
    }

    private var everyoneKept: Bool {
        standings.count >= 2 && keptCount == standings.count
    }

    private var labelText: String {
        if everyoneKept {
            return "Everyone kept today"
        }
        return "\(keptCount) of \(standings.count) kept today"
    }

    private var label: some View {
        Text(labelText)
            .font(Fonts.footnoteSemibold)
            .foregroundStyle(everyoneKept ? Ink.text : Ink.text2)
            .multilineTextAlignment(.center)
            .rollingNumber(Double(keptCount))
            .padding(.horizontal, Gap.gutter)
    }

    // MARK: - Faces

    private func makeFaces() -> [Face] {
        let names: [String] = NameFormat.shortNames(standings.map { (s: MemberStanding) -> String in s.displayName })
        var out: [Face] = []
        for (index, s) in standings.enumerated() {
            let isYou: Bool = s.userID == viewerID
            let state: SphereState
            if isYou {
                state = viewerLit ? .lit : .open
            } else {
                state = s.checkedInToday ? .lit : .unlit
            }
            let name: String = isYou ? "You" : names[index]
            out.append(Face(id: s.userID, name: name, initial: NameFormat.initial(s.displayName), state: state, isYou: isYou))
        }
        return out
    }

    /// One centred row when it fits, else a wrapping grid.
    private func cells(_ faces: [Face]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: MemberStrip.spacing) {
                cellItems(faces)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cell), spacing: MemberStrip.spacing)], spacing: Gap.m) {
                cellItems(faces)
            }
        }
        .padding(.horizontal, Gap.l)
    }

    private func cellItems(_ faces: [Face]) -> some View {
        ForEach(faces) { (face: Face) in
            memberCell(face)
        }
    }

    private func memberCell(_ face: Face) -> some View {
        Button {
            onMember(face.id)
        } label: {
            VStack(spacing: Gap.xs) {
                Sphere(theme: theme,
                       state: face.state,
                       size: MemberStrip.sphereSize,
                       initial: face.initial,
                       ringColor: atRisk ? Ink.flame : Ink.text)
                    .animation(Anim.light, value: face.state)
                Text(face.name)
                    .font(face.isYou ? Fonts.captionBold : Fonts.caption)
                    .foregroundStyle(face.isYou ? Ink.text : Ink.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: cell)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(face.name)
        .accessibilityValue(status(face))
        .accessibilityShowsLargeContentViewer {
            Label(face.name, systemImage: face.state == .lit ? "circle.fill" : "circle")
        }
    }

    private func status(_ face: Face) -> String {
        if face.state == .lit {
            return "kept today"
        }
        return face.isYou ? "your turn" : "not yet"
    }
}
