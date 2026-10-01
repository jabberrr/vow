import SwiftUI

/// Fixed-height group header: name (+ TEST chip or next-day countdown) and the cycle / day mono bits.
struct HeaderView: View {
    let group: GroupInfo
    let cycle: Int
    let day: Int

    private var cycleText: String {
        "Cycle " + String(format: "%02d", cycle)
    }

    private var dayText: String {
        "Day \(day) / 30"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            titleColumn
            Spacer(minLength: 12)
            cycleColumn
        }
        .frame(height: 56)
        .padding(.horizontal, 4)
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.name)
                .font(Theme.display(26, .heavy))
                .gradientText()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            subline
                .frame(height: 18, alignment: .leading)
        }
    }

    @ViewBuilder
    private var subline: some View {
        if group.isTest {
            Badge(text: "Test", color: Theme.amber)
                .scaleEffect(0.9, anchor: .leading)
        } else {
            NextDayCountdown(group: group)
        }
    }

    private var cycleColumn: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(cycleText)
                .font(Theme.mono(12, .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.85))
            Text(dayText)
                .font(Theme.mono(12, .medium))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }
}

/// "next day in 5h 12m". Pure display inside the TimelineView (no state, no side effects).
private struct NextDayCountdown: View {
    let group: GroupInfo

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(NextDayCountdown.text(group: group, now: context.date))
                .font(Theme.mono(11, .medium))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    static func text(group: GroupInfo, now: Date) -> String {
        guard let next = DayClock.nextDayStart(group, now: now) else { return "" }
        let seconds: Int = max(0, Int(next.timeIntervalSince(now)))
        let hours: Int = seconds / 3600
        let minutes: Int = (seconds % 3600) / 60
        if hours > 0 {
            return "next day in \(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "next day in \(minutes)m"
        }
        return "next day in <1m"
    }
}
