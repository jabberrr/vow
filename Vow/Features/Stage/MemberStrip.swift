import SwiftUI

/// Who kept today, at the moment of action: "2 of 4 kept today" over a row of faces lit in the day's
/// colours (you: lit or ringed), dashed for an excuse that stands and unlit for a claim the group has
/// overruled. Anyone sitting the day out on an excuse is left out of the count. The faces and the count
/// read `MemberDay` and `KeptNote`, as the Group page does. Only the people in the group: inviting lives
/// on the Group page. Wraps into rows instead of scrolling, so nobody is hidden.
struct MemberStrip: View {
    let theme: DailyTheme
    let standings: [MemberStanding]
    let viewerID: String
    /// Your check-in lights your sphere and your place in the count at the social beat, not at the seal.
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
        let status: MemberDay
        let isYou: Bool
    }

    private static let sphereSize: CGFloat = 40
    private static let spacing: CGFloat = 4

    var body: some View {
        let faces: [Face] = makeFaces()
        let note: KeptNote = KeptNote(faces.map { (face: Face) -> MemberDay in face.status })
        VStack(spacing: 0) {
            label(note)
            cells(faces)
                .padding(.top, rowTop)
        }
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: - Label

    /// Counted from the faces, so your place in it lights with your sphere.
    private func label(_ note: KeptNote) -> some View {
        Text(note.text)
            .font(Fonts.footnoteSemibold)
            .foregroundStyle(note.everyoneKept ? Ink.text : Ink.text2)
            .multilineTextAlignment(.center)
            .rollingNumber(Double(note.kept))
            .padding(.horizontal, Gap.gutter)
            .accessibilityLabel(note.spoken)
    }

    // MARK: - Faces

    private func makeFaces() -> [Face] {
        let names: [String] = NameFormat.shortNames(standings.map { (s: MemberStanding) -> String in s.displayName })
        var out: [Face] = []
        for (index, s) in standings.enumerated() {
            let isYou: Bool = s.userID == viewerID
            let status: MemberDay = MemberDay.of(s, isViewer: isYou, viewerLit: viewerLit)
            let name: String = isYou ? "You" : names[index]
            out.append(Face(id: s.userID, name: name, initial: NameFormat.initial(s.displayName), status: status, isYou: isYou))
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
                       state: face.status.sphere,
                       size: MemberStrip.sphereSize,
                       initial: face.initial,
                       ringColor: atRisk ? Ink.flame : Ink.text)
                    .animation(Anim.light, value: face.status)
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
        .accessibilityValue(face.status.phrase)
        .accessibilityShowsLargeContentViewer {
            Label(face.name, systemImage: MemberStrip.symbol(face.status))
        }
    }

    private static func symbol(_ status: MemberDay) -> String {
        switch status {
        case .kept: return "circle.fill"
        case .excused: return "circle.dashed"
        case .yourTurn, .notYet, .overruled: return "circle"
        }
    }
}
