import SwiftUI

/// Streak numeral and best, the 30-bead cycle string, and the cycle/day caption.
/// The streak rolls and today's bead fills on the reward beat (0.25 s after the seal).
/// GroupColumn caps Dynamic Type at AX2 around it, so `streakSize` sees the cap too.
struct ProgressSection: View {
    let viewer: MemberStanding
    let summary: GroupSummary
    let rewardToken: Int
    @ScaledMetric(relativeTo: .largeTitle) private var streakSize: CGFloat = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    private var best: Int {
        max(viewer.bestStreak, viewer.streak)
    }

    var body: some View {
        let days: [CycleDay] = CycleDay.make(history: viewer.history,
                                             currentDay: summary.currentDay,
                                             sealedToday: viewer.checkedInToday)
        return VStack(alignment: .leading, spacing: 0) {
            streakRow
            CycleBeads(days: days, rewardToken: rewardToken)
                .frame(height: 18)
                .padding(.top, 14)
            Text("Cycle \(summary.cycle) · Day \(summary.dayInCycle) of 30")
                .font(Typeface.footnote)
                .foregroundStyle(Palette.text3)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(days))
    }

    private var streakRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                numeral
                dayStreak
                Spacer(minLength: 8)
                bestText
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    numeral
                    dayStreak
                }
                bestText
            }
        }
    }

    private var numeral: some View {
        Text("\(viewer.streak)")
            .font(Font.system(size: streakSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Palette.text)
            .contentTransition(.numericText(value: Double(viewer.streak)))
            .animation(reduceMotion ? Motion.rewardFade : Motion.reward, value: viewer.streak)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private var dayStreak: some View {
        Text("day streak")
            .font(Typeface.subheadline)
            .foregroundStyle(Palette.text2)
    }

    private var bestText: some View {
        Text("Best \(best)")
            .font(Typeface.subheadline)
            .foregroundStyle(Palette.text2)
    }

    /// "12-day streak, best 13. Cycle 1, day 20 of 30. 18 kept, 1 missed."
    private func spoken(_ days: [CycleDay]) -> String {
        var kept: Int = 0
        var missed: Int = 0
        for day in days {
            switch day {
            case .kept:
                kept += 1
            case .missed:
                missed += 1
            case .today(let sealed):
                if sealed {
                    kept += 1
                }
            case .inactive, .future:
                break
            }
        }
        let streakPart: String = "\(viewer.streak)-day streak, best \(best)."
        let cyclePart: String = "Cycle \(summary.cycle), day \(summary.dayInCycle) of 30."
        return streakPart + " " + cyclePart + " \(kept) kept, \(missed) missed."
    }
}

/// One slot of the current 30-day cycle.
enum CycleDay: Equatable {
    case kept, missed, inactive, future
    case today(sealed: Bool)

    /// The 30 slots of the current cycle (pure). `history` is the viewer's closed participating days,
    /// oldest first, ending yesterday. Day 1 of a new cycle deliberately starts a fresh string.
    static func make(history: [DayOutcome], currentDay: Int, sealedToday: Bool) -> [CycleDay] {
        let cycleStart: Int = (currentDay / 30) * 30
        let firstHistoryDay: Int = currentDay - history.count
        var days: [CycleDay] = []
        days.reserveCapacity(30)
        for i in 0..<30 {
            let d: Int = cycleStart + i
            if d > currentDay {
                days.append(CycleDay.future)
            } else if d == currentDay {
                days.append(CycleDay.today(sealed: sealedToday))
            } else {
                let idx: Int = d - firstHistoryDay
                if idx < 0 || idx >= history.count {
                    days.append(CycleDay.inactive)
                } else {
                    let outcome: CycleDay = history[idx] == DayOutcome.kept ? CycleDay.kept : CycleDay.missed
                    days.append(outcome)
                }
            }
        }
        return days
    }
}

/// The bead string. Decorative (ProgressSection speaks the counts).
struct CycleBeads: View {
    let days: [CycleDay]
    let rewardToken: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<days.count, id: \.self) { i in
                bead(days[i])
                    .frame(maxWidth: .infinity)
                    .zIndex(layer(days[i]))
            }
        }
    }

    /// Exactly one `.today` branch, so today's bead keeps its identity (and animations) through the seal.
    @ViewBuilder
    private func bead(_ day: CycleDay) -> some View {
        switch day {
        case .kept:
            Circle()
                .fill(Palette.kept)
                .frame(width: 8, height: 8)
        case .missed:
            Circle()
                .strokeBorder(Palette.loss, lineWidth: 1.5)
                .frame(width: 8, height: 8)
        case .inactive:
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 4, height: 4)
        case .future:
            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 6, height: 6)
        case .today(let sealed):
            TodayBead(sealed: sealed, rewardToken: rewardToken)
        }
    }

    /// Today's bead draws above its neighbours so the ripple passes over them.
    private func layer(_ day: CycleDay) -> Double {
        if case .today = day {
            return 1
        }
        return 0
    }
}

/// Today's bead: an accent ring while open; on the reward beat the ring gives way to a kept dot that
/// springs 0.4 -> 1 with a halo, and a kept ripple runs out once on `rewardToken`. Everything is always
/// mounted so the animations have something to animate.
struct TodayBead: View {
    let sealed: Bool
    let rewardToken: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.accent, lineWidth: 2)
                .opacity(sealed ? 0 : 1)
            Circle()
                .stroke(Palette.kept.opacity(0.18), lineWidth: 3)
                .frame(width: 18, height: 18)
                .opacity(sealed ? 1 : 0)
            Circle()
                .fill(Palette.kept)
                .scaleEffect(sealed || reduceMotion ? 1 : 0.4)
                .opacity(sealed ? 1 : 0)
            ripple
        }
        .frame(width: 12, height: 12)
        .animation(reduceMotion ? Motion.rewardFade : Motion.reward, value: sealed)
    }

    private var ripple: some View {
        Circle()
            .stroke(Palette.kept, lineWidth: 1.5)
            .keyframeAnimator(initialValue: RippleValue(), trigger: reduceMotion ? 0 : rewardToken) { content, value in
                content
                    .scaleEffect(value.scale)
                    .opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\RippleValue.scale) {
                    LinearKeyframe(1.0, duration: 0.01)
                    CubicKeyframe(2.6, duration: 0.6)
                }
                KeyframeTrack(\RippleValue.opacity) {
                    LinearKeyframe(0.8, duration: 0.01)
                    CubicKeyframe(0.0, duration: 0.6)
                }
            }
    }
}

/// Keyframed values for today's bead ripple (invisible at rest).
struct RippleValue {
    var scale: CGFloat = 1
    var opacity: Double = 0
}
