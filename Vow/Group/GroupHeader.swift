import SwiftUI

/// GroupHeader's frame in GroupView's scroll space; drives the nav bar title once the header scrolls away.
struct GroupHeaderFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Group name over one meta line: time left and the stake while your day is open, else the next-day
/// countdown (test groups: the Test chip, plus the stake while open). The meta line holds both phrasings
/// at all times, so its height never changes on check-in and the orb below never moves.
struct GroupHeader: View {
    let group: GroupInfo
    let sealed: Bool
    let isMember: Bool

    private var isOpen: Bool {
        isMember && !sealed
    }

    private var stakeText: String {
        GroupFormat.stake(group.stake) + " at stake"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.name)
                .font(Typeface.title)
                .foregroundStyle(Palette.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            metaRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(frameReporter)
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if group.isTest {
                Chip("Test")
            }
            metaText
        }
        .frame(minHeight: 20, alignment: .leading)
    }

    @ViewBuilder
    private var metaText: some View {
        if group.isTest {
            phrasings(open: stakeText, closed: "")
        } else {
            TimelineView(.everyMinute) { context in
                phrasings(open: openText(now: context.date), closed: closedText(now: context.date))
            }
        }
    }

    /// Both phrasings stacked; the inactive one is invisible. The swap is not animated.
    private func phrasings(open: String, closed: String) -> some View {
        ZStack(alignment: .leading) {
            Text(open)
                .opacity(isOpen ? 1 : 0)
                .accessibilityHidden(!isOpen)
            Text(closed)
                .opacity(isOpen ? 0 : 1)
                .accessibilityHidden(isOpen || closed.isEmpty)
        }
        .font(Typeface.subheadline)
        .foregroundStyle(Palette.text2)
        .fixedSize(horizontal: false, vertical: true)
        .animation(nil, value: isOpen)
    }

    /// "7h 18m", "18m", or nil under a minute.
    private func span(now: Date) -> String? {
        guard let next: Date = DayClock.nextDayStart(group, now: now) else { return nil }
        let seconds: Int = max(0, Int(next.timeIntervalSince(now)))
        let hours: Int = seconds / 3600
        let minutes: Int = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return nil
    }

    private func openText(now: Date) -> String {
        if let left: String = span(now: now) {
            return "\(left) left · \(stakeText)"
        }
        return "Under a minute left · \(stakeText)"
    }

    private func closedText(now: Date) -> String {
        if let left: String = span(now: now) {
            return "Next day in \(left)"
        }
        return "Next day in under a minute"
    }

    private var frameReporter: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: GroupHeaderFrameKey.self, value: proxy.frame(in: .named(GroupView.scrollSpace)))
        }
    }
}

/// The vow above the orb: lead-in words in Palette.text3, the rest in Palette.text. Tap to edit.
struct VowLine: View {
    let vow: String
    let onEdit: () -> Void

    /// Extra vertical hit area above and below the text.
    static let tapPadding: CGFloat = 10

    var body: some View {
        Button(action: onEdit) {
            styled
                .font(Typeface.title3)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 12)
                // 44pt+ tap target; GroupColumn trims the spacing around it so the orb doesn't move.
                .padding(.vertical, VowLine.tapPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel(vow)
        .accessibilityHint("Edit vow")
    }

    private var styled: Text {
        let parts: (prefix: String, verb: String, suffix: String) = VowText.split(vow)
        if parts.verb.isEmpty {
            return Text(vow).foregroundStyle(Palette.text)
        }
        let head: Text = Text(parts.prefix).foregroundStyle(Palette.text3)
        let rest: Text = Text(parts.verb + parts.suffix).foregroundStyle(Palette.text)
        return head + rest
    }
}

/// "Hold to check in" under the active orb, "✓ Checked in" under the sealed one. Both labels stay
/// mounted (the checkmark bounces on `settleToken`); `highlighted` flashes the instruction in accent
/// after a too-short press. Hidden from VoiceOver: the orb's own label says the same.
struct CheckInStatus: View {
    let sealed: Bool
    let highlighted: Bool
    let settleToken: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        ZStack {
            Text("Hold to check in")
                .font(Typeface.subheadlineMedium)
                .foregroundStyle(highlighted ? Palette.accent : Palette.text2)
                .opacity(sealed ? 0 : 1)
            checkedIn
                .opacity(sealed ? 1 : 0)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 22)
        .animation(Motion.fade, value: sealed)
        .animation(Motion.fade, value: highlighted)
        .accessibilityHidden(true)
    }

    private var checkedIn: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .fontWeight(.bold)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : settleToken)
            Text("Checked in")
        }
        .font(Typeface.subheadlineSemibold)
        .foregroundStyle(Palette.kept)
    }
}
