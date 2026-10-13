import SwiftUI

/// The vow's name as a menu of its own actions, over one quiet meta line: the Test tag, the day of
/// the cycle, the stake, and the Pot tag when yesterday's pot carried over.
struct StageHeader: View {
    let group: GroupInfo
    let summary: GroupSummary
    let isMember: Bool
    let isOwner: Bool
    /// Owner of a test group in testing mode: Next day and Reset group.
    let canAdvance: Bool
    let testBusy: Bool
    let onEditVow: () -> Void
    let onInvite: () -> Void
    let onRefresh: () -> Void
    let onNextDay: () -> Void
    let onResetGroup: () -> Void
    let onLeave: () -> Void
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize: DynamicTypeSize

    init(group: GroupInfo,
         summary: GroupSummary,
         isMember: Bool,
         isOwner: Bool,
         canAdvance: Bool,
         testBusy: Bool,
         onEditVow: @escaping () -> Void,
         onInvite: @escaping () -> Void,
         onRefresh: @escaping () -> Void,
         onNextDay: @escaping () -> Void,
         onResetGroup: @escaping () -> Void,
         onLeave: @escaping () -> Void,
         onDelete: @escaping () -> Void) {
        self.group = group
        self.summary = summary
        self.isMember = isMember
        self.isOwner = isOwner
        self.canAdvance = canAdvance
        self.testBusy = testBusy
        self.onEditVow = onEditVow
        self.onInvite = onInvite
        self.onRefresh = onRefresh
        self.onNextDay = onNextDay
        self.onResetGroup = onResetGroup
        self.onLeave = onLeave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            titleMenu
            meta
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Title menu

    private var titleMenu: some View {
        Menu {
            menuItems
        } label: {
            titleLabel
        }
        .accessibilityLabel("\(group.name), vow options")
        .padding(.horizontal, Gap.gutter)
    }

    private var titleLabel: some View {
        HStack(spacing: 5) {
            Text(group.name)
                .font(Fonts.headline)
                .foregroundStyle(Ink.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .multilineTextAlignment(.center)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Ink.text3)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Gap.s)
        .frame(minHeight: Gap.hit)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(action: onEditVow) {
            Label(editTitle, systemImage: "pencil")
        }
        if isMember {
            Button(action: onInvite) {
                Label("Invite", systemImage: "person.badge.plus")
            }
        }
        Button(action: onRefresh) {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        if canAdvance {
            testItems
        }
        Divider()
        destructiveItem
    }

    private var editTitle: String {
        isMember ? "Edit vow" : "Write your vow"
    }

    @ViewBuilder
    private var testItems: some View {
        Button(action: onNextDay) {
            Label("Next day", systemImage: "forward.fill")
        }
        .disabled(testBusy)
        Button(action: onResetGroup) {
            Label("Reset group", systemImage: "arrow.counterclockwise")
        }
        .disabled(testBusy)
    }

    @ViewBuilder
    private var destructiveItem: some View {
        if isOwner {
            Button(role: .destructive, action: onDelete) {
                Label("Delete group", systemImage: "trash")
            }
        } else {
            Button(role: .destructive, action: onLeave) {
                Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    // MARK: - Meta line

    private var dayText: String {
        "Day \(summary.dayInCycle) of 30"
    }

    private var stakeText: String {
        StakeText.perDay(group.stake)
    }

    private var hasPot: Bool {
        (summary.pot * 100).rounded() > 0
    }

    /// One line when it fits; otherwise a centred column, so nothing is clipped at large sizes.
    private var meta: some View {
        ViewThatFits(in: .horizontal) {
            metaRow
            metaColumn
        }
        .font(Fonts.footnoteMedium)
        .foregroundStyle(Ink.text2)
        .padding(.horizontal, Gap.gutter)
        .accessibilityElement(children: .combine)
    }

    private var metaRow: some View {
        HStack(spacing: 7) {
            if group.isTest {
                testTag
            }
            Text(dayText)
                .lineLimit(1)
            Text("·")
                .accessibilityHidden(true)
            Text(stakeText)
                .lineLimit(1)
            if hasPot {
                potTag
            }
        }
    }

    private var metaColumn: some View {
        VStack(spacing: Gap.xs) {
            if group.isTest {
                testTag
            }
            Text(dayText + " · " + stakeText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if hasPot {
                potTag
            }
        }
    }

    private var testTag: some View {
        Tag("Test")
    }

    private var potTag: some View {
        Tag("Pot " + PointsText.string(summary.pot), systemImage: "arrow.uturn.forward", style: .gain)
    }
}
