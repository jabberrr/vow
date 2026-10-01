import SwiftUI

struct VowCard: View {
    let vow: String
    let groupName: String
    /// Preformatted, e.g. "2 pts".
    let stake: String
    /// Preformatted join date ("Oct 1") or test day ("Day 3").
    let since: String

    private var vowText: Text {
        let parts = VowText.split(vow)
        let head: Text = Text(parts.prefix).foregroundStyle(Color.white)
        let verb: Text = Text(parts.verb).foregroundStyle(Theme.brand)
        let tail: Text = Text(parts.suffix).foregroundStyle(Color.white)
        return head + verb + tail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your vow · daily")
                .eyebrow()
            vowText
                .font(Theme.display(22, .semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            cells
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var cells: some View {
        HStack(alignment: .top, spacing: 12) {
            VowStatCell(label: "Group", value: groupName)
            VowStatCell(label: "Stake", value: stake)
            VowStatCell(label: "Since", value: since)
        }
    }
}

private struct VowStatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .eyebrow()
            Text(value)
                .font(Theme.mono(14, .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
