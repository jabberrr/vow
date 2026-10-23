import SwiftUI

/// One day of the Activity page, with no card: a small header, then its lines. Notes are quiet; a stake lost
/// reads in full with its points on the right, then an indented arrow line for each place they went. A day
/// with nothing but one note keeps it on the header's line while that fits ("Tue, Oct 20 … Everyone kept").
struct ActivityDayView: View {
    let section: ActivitySection

    init(section: ActivitySection) {
        self.section = section
    }

    @ViewBuilder
    var body: some View {
        if let note: ActivityNote = section.quietNote {
            ViewThatFits(in: .horizontal) {
                quietLine(note)
                stacked
            }
        } else {
            stacked
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: Gap.s) {
            header
            VStack(alignment: .leading, spacing: Gap.m) {
                ForEach(section.items) { (item: ActivityItem) in
                    itemView(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Yesterday", with "Votes still open" trailing while its points can still change. One VoiceOver header:
    /// "Yesterday, votes still open".
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
            title
            if section.votesOpen {
                Spacer(minLength: Gap.s)
                Text("Votes still open")
                    .font(Fonts.footnote)
                    .foregroundStyle(Ink.text3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.spokenTitle)
        .accessibilityAddTraits(.isHeader)
    }

    private var title: some View {
        Text(section.title)
            .font(Fonts.footnoteSemibold)
            .foregroundStyle(Ink.text2)
    }

    /// The header and the day's one note on a line: VoiceOver reads the header, then the note.
    private func quietLine(_ note: ActivityNote) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
            title
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Gap.l)
            noteText(note)
        }
    }

    @ViewBuilder
    private func itemView(_ item: ActivityItem) -> some View {
        switch item {
        case .note(let note):
            noteText(note)
                .fixedSize(horizontal: false, vertical: true)
        case .flow(let flow):
            ActivityFlowView(flow: flow)
        }
    }

    /// A note reads the same on the header's line as under it, so a quiet day that no longer fits there (large
    /// text) keeps its look.
    private func noteText(_ note: ActivityNote) -> some View {
        Text(note.text)
            .font(Fonts.subheadline)
            .foregroundStyle(Ink.text2)
            .accessibilityLabel(note.spoken)
    }
}

/// A stake lost (or the pot carried in) and its arrow lines, read by VoiceOver as one element: "Maya missed,
/// minus 2 points. 1 point to you, 1 point to Sam".
private struct ActivityFlowView: View {
    let flow: ActivityFlow

    init(flow: ActivityFlow) {
        self.flow = flow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Gap.xs) {
            ActivityLineRow(line: flow.source, isArrow: false)
            ForEach(flow.arrows) { (arrow: ActivityLine) in
                ActivityLineRow(line: arrow, isArrow: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(flow.spoken)
    }
}

/// Words on the left and points on the right; an arrow line is indented behind its arrow. Only your own
/// points take colour; everyone else's stay grey. At accessibility sizes the points go under the words.
private struct ActivityLineRow: View {
    let line: ActivityLine
    let isArrow: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize: DynamicTypeSize

    init(line: ActivityLine, isArrow: Bool) {
        self.line = line
        self.isArrow = isArrow
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Gap.s) {
            if isArrow {
                arrow
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Gap.xxs) {
                    label
                    amount
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                label
                Spacer(minLength: Gap.s)
                amount
            }
        }
        .padding(.leading, isArrow ? Gap.xs : 0)
    }

    private var arrow: some View {
        Image(systemName: "arrow.turn.down.right")
            .font(Fonts.footnoteSemibold)
            .foregroundStyle(Ink.text3)
    }

    /// A stake lost reads bright; an arrow's name reads grey unless it is you.
    private var label: some View {
        Text(line.text)
            .font(Fonts.subheadline)
            .foregroundStyle(isArrow && !line.isViewer ? Ink.text2 : Ink.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var amount: some View {
        Text(line.amountText)
            .font(line.isViewer ? Fonts.subheadlineSemibold : Fonts.subheadline)
            .monospacedDigit()
            .foregroundStyle(line.isViewer ? Ink.points(line.amount) : Ink.text2)
            .layoutPriority(1)
    }
}
