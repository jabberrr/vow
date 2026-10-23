import SwiftUI

/// "Members" on the Group page: everyone in `summary.standings` order (you first, then by name) with
/// today's status, streak and net, then Invite. Only your own net is coloured; friends' nets stay grey,
/// streaks carry the comparison, and a friend who hasn't checked in yet is "not yet", never "missed".
/// Someone sitting today out on an excuse has a dashed ring and drops out of the kept count. The owner
/// has a crown by their name.
struct GroupMembersCard: View {
    let summary: GroupSummary
    let viewerID: String
    /// `GroupInfo.ownerUserID`.
    let ownerID: String
    /// The last 4 h of a real group's day: your open ring turns flame.
    let atRisk: Bool
    /// Members of an unfinished group: Invite closes the list it adds to.
    let canInvite: Bool
    let onSelect: (String) -> Void
    let onInvite: () -> Void

    init(summary: GroupSummary,
         viewerID: String,
         ownerID: String,
         atRisk: Bool,
         canInvite: Bool,
         onSelect: @escaping (String) -> Void,
         onInvite: @escaping () -> Void) {
        self.summary = summary
        self.viewerID = viewerID
        self.ownerID = ownerID
        self.atRisk = atRisk
        self.canInvite = canInvite
        self.onSelect = onSelect
        self.onInvite = onInvite
    }

    /// Home's strip count. None once the vow is finished, since nobody has a today then.
    private var keptNote: KeptNote? {
        guard !summary.isFinished, !summary.standings.isEmpty else { return nil }
        return KeptNote(summary.standings.map { (s: MemberStanding) -> MemberDay in
            MemberDay.of(s, isViewer: s.userID == viewerID)
        })
    }

    var body: some View {
        let theme: DailyTheme = Overview.theme(summary)
        return VStack(alignment: .leading, spacing: 0) {
            header
            card(theme)
        }
    }

    /// One VoiceOver header: "Members", with the count as its value.
    private var header: some View {
        let note: KeptNote? = keptNote
        return SectionTitle("Members", trailing: note?.text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Members")
            .accessibilityValue(note?.spoken ?? "")
            .accessibilityAddTraits(.isHeader)
    }

    private func card(_ theme: DailyTheme) -> some View {
        VStack(spacing: 0) {
            ForEach(summary.standings) { (row: MemberStanding) in
                if row.userID != summary.standings.first?.userID {
                    Hairline(leading: 62)
                }
                GroupMemberRow(row: row,
                               theme: theme,
                               isViewer: row.userID == viewerID,
                               isOwner: row.userID == ownerID,
                               isFinished: summary.isFinished,
                               atRisk: atRisk,
                               onSelect: onSelect)
            }
            if canInvite {
                if !summary.standings.isEmpty {
                    Hairline(leading: 62)
                }
                GroupInviteRow(action: onInvite)
            }
        }
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

/// Sphere, name (with the owner's crown) over short vow; streak over net on the right. A button that opens
/// the member sheet. The Group page is never on screen during a check-in, so every value is the store's.
private struct GroupMemberRow: View {
    let row: MemberStanding
    let theme: DailyTheme
    let isViewer: Bool
    let isOwner: Bool
    let isFinished: Bool
    let atRisk: Bool
    let onSelect: (String) -> Void

    init(row: MemberStanding,
         theme: DailyTheme,
         isViewer: Bool,
         isOwner: Bool,
         isFinished: Bool,
         atRisk: Bool,
         onSelect: @escaping (String) -> Void) {
        self.row = row
        self.theme = theme
        self.isViewer = isViewer
        self.isOwner = isOwner
        self.isFinished = isFinished
        self.atRisk = atRisk
        self.onSelect = onSelect
    }

    /// nil once the vow is finished: nobody has a today then.
    private var today: MemberDay? {
        isFinished ? nil : MemberDay.of(row, isViewer: isViewer)
    }

    /// Nobody is lit or ringed once the vow is finished.
    private var state: SphereState {
        today?.sphere ?? .unlit
    }

    private var name: String {
        isViewer ? "You" : MemberText.name(row.displayName)
    }

    private var shortVow: String {
        VowFormat.short(row.vow)
    }

    private var nameFont: Font {
        isViewer ? Fonts.subheadlineSemibold : Fonts.subheadlineMedium
    }

    /// "Maya, owner, Swim 40 lengths, kept today, 21-day streak, plus 6.25 points"
    private var spoken: String {
        var parts: [String] = [MemberText.spokenName(name, isOwner: isOwner)]
        if !shortVow.isEmpty {
            parts.append(shortVow)
        }
        if let day: MemberDay = today {
            parts.append(day.phrase)
        }
        parts.append(row.streak == 1 ? "1-day streak" : "\(row.streak)-day streak")
        parts.append(MemberText.netSpoken(row.net))
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button {
            onSelect(row.userID)
        } label: {
            HStack(spacing: 14) {
                sphere
                nameColumn
                Spacer(minLength: Gap.s)
                trailingColumn
            }
            .padding(.horizontal, Gap.l)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
        }
        .buttonStyle(RowPressStyle())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(spoken)
    }

    private var sphere: some View {
        Sphere(theme: theme,
               state: state,
               size: 32,
               initial: NameFormat.initial(row.displayName),
               ringColor: atRisk ? Ink.flame : Ink.text,
               glows: false)
            .animation(Anim.light, value: state)
    }

    private var nameColumn: some View {
        VStack(alignment: .leading, spacing: Gap.xxs) {
            nameLine
            if !shortVow.isEmpty {
                Text(shortVow)
                    .font(Fonts.footnote)
                    .foregroundStyle(Ink.text2)
                    .lineLimit(1)
            }
        }
    }

    /// The name truncates before the crown does.
    private var nameLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.xs) {
            Text(name)
                .font(nameFont)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
            if isOwner {
                OwnerCrown(font: nameFont)
            }
        }
    }

    /// Kept whole: the name and vow truncate first.
    private var trailingColumn: some View {
        VStack(alignment: .trailing, spacing: Gap.xxs) {
            FlameStreak(count: row.streak, size: .small)
            Text(MemberText.net(row.net))
                .font(isViewer ? Fonts.footnoteSemibold : Fonts.footnote)
                .monospacedDigit()
                .foregroundStyle(isViewer ? Ink.points(row.net) : Ink.text2)
                .lineLimit(1)
        }
        .layoutPriority(1)
    }
}

/// Invite as an empty seat at the end of the list it adds to: a solid disc with a plus, like the sidebar's
/// Add group (a dashed ring means excused).
private struct GroupInviteRow: View {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                seat
                Text("Invite")
                    .font(Fonts.subheadlineSemibold)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Gap.l)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
        }
        .buttonStyle(RowPressStyle())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel("Invite")
    }

    private var seat: some View {
        Image(systemName: "plus")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Ink.text)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Ink.field))
            .accessibilityHidden(true)
    }
}

/// Where a member's today stands, the one reading behind Home's strip, the Group page and the member sheet:
/// a check-in or an excuse that stands, either one overruled by the votes so far, your turn, or a friend's
/// "not yet" (never "missed").
enum MemberDay: Equatable {
    case kept, excused, overruled, yourTurn, notYet

    /// `viewerLit` is Home's hold: your check-in lights your sphere and your place in the count at the
    /// cascade's social beat, not at the seal, so until then it is still your turn. An excuse shows at once
    /// (it lands behind its sheet). Nothing else is on screen during a check-in, so it holds nothing.
    static func of(_ member: MemberStanding, isViewer: Bool, viewerLit: Bool = true) -> MemberDay {
        if isViewer && member.checkedInToday && !viewerLit {
            return .yourTurn
        }
        if Digest.checkInStands(member) {
            return .kept
        }
        if Digest.excuseStands(member) {
            return .excused
        }
        if member.checkedInToday || member.excusedToday {
            return .overruled
        }
        return isViewer ? .yourTurn : .notYet
    }

    /// Lit while a check-in stands, a dashed ring while an excuse stands, ringed on your turn; an
    /// overruled claim and a friend's "not yet" are unlit.
    var sphere: SphereState {
        switch self {
        case .kept: return .lit
        case .excused: return .excused
        case .yourTurn: return .open
        case .overruled, .notYet: return .unlit
        }
    }

    /// Within a spoken row: "kept today", "excused today", "overruled", "your turn", "not yet".
    var phrase: String {
        switch self {
        case .kept: return "kept today"
        case .excused: return "excused today"
        case .overruled: return "overruled"
        case .yourTurn: return "your turn"
        case .notYet: return "not yet"
        }
    }

    /// On its own (the member sheet): "Kept today", "Excused today", "Overruled", "Your turn", "Not yet".
    var title: String {
        switch self {
        case .kept: return "Kept today"
        case .excused: return "Excused today"
        case .overruled: return "Overruled"
        case .yourTurn: return "Your turn"
        case .notYet: return "Not yet"
        }
    }
}

/// Today's count, from the same `MemberDay`s the spheres show, so the two never disagree: "2 of 4 kept today",
/// "Everyone kept today" (two or more), "Everyone's excused today". Anyone sitting the day out on an excuse
/// that stands is left out of it. Home's strip and the Group page's Members header both say it.
struct KeptNote {
    let kept: Int
    let excused: Int
    /// Everyone the day counts: all but the excused.
    let counted: Int

    init(_ days: [MemberDay]) {
        var kept: Int = 0
        for day in days where day == .kept {
            kept += 1
        }
        var excused: Int = 0
        for day in days where day == .excused {
            excused += 1
        }
        self.kept = kept
        self.excused = excused
        self.counted = days.count - excused
    }

    var everyoneKept: Bool {
        counted >= 2 && kept == counted
    }

    var text: String {
        if counted == 0 && excused > 0 {
            return "Everyone's excused today"
        }
        if everyoneKept {
            return "Everyone kept today"
        }
        return "\(kept) of \(counted) kept today"
    }

    /// The text, and how many sit today out unless everyone does: "2 of 4 kept today, 1 excused".
    var spoken: String {
        if excused == 0 || counted == 0 {
            return text
        }
        return text + ", \(excused) excused"
    }
}

/// The owner's mark beside their name, on the Group page and in the member sheet: a small crown in the name's
/// own font, so it scales with it. Neutral, because it is a role and not a status. VoiceOver hears "owner" in
/// the label it sits by instead (`MemberText.spokenName`).
struct OwnerCrown: View {
    let font: Font

    init(font: Font) {
        self.font = font
    }

    var body: some View {
        Image(systemName: "crown.fill")
            .font(font)
            .imageScale(.small)
            .foregroundStyle(Ink.text2)
            .accessibilityHidden(true)
    }
}

/// A member's name and net for display. Nets read like balances: signed unless zero ("+4.5 pts", "0 pts").
enum MemberText {
    /// Trimmed display name; empty -> "Someone", as Activity says it (`ActivityFeed.name`).
    static func name(_ displayName: String) -> String {
        let trimmed: String = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Someone" : trimmed
    }

    /// "Maya, owner" for the owner (whose crown VoiceOver doesn't read); otherwise the name as shown.
    static func spokenName(_ name: String, isOwner: Bool) -> String {
        return isOwner ? name + ", owner" : name
    }

    /// "+4.5 pts", "−2 pts", "0 pts".
    static func net(_ value: Double) -> String {
        let parts: (number: String, unit: String) = PointsText.balanceParts(value)
        return parts.unit.isEmpty ? parts.number : parts.number + " " + parts.unit
    }

    /// "+6.25" (a stat whose label carries the unit).
    static func netNumber(_ value: Double) -> String {
        PointsText.balanceParts(value).number
    }

    /// "plus 6.25 points", "0 points".
    static func netSpoken(_ value: Double) -> String {
        let isZero: Bool = (abs(value) * 100).rounded() == 0
        return PointsText.spoken(value, signed: !isZero)
    }
}
