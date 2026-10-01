import SwiftUI

struct PotCard: View {
    /// Unsplit carry after the last closed day.
    let pot: Double
    let totalForfeited: Double
    /// Viewer's net in this group.
    let net: Double

    private var netColor: Color {
        net >= 0 ? Theme.lime : Theme.pink
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pot · forfeited so far")
                .eyebrow()
            Text(Points.format(totalForfeited))
                .font(Theme.mono(36, .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            carryLine
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            netRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var carryLine: some View {
        if pot > 0 {
            Text("Carrying " + Points.format(pot) + " · nobody kept")
                .font(Theme.mono(12, .medium))
                .foregroundStyle(Theme.amber)
        } else {
            Text("Misses fill the pot; keepers split it.")
                .font(Theme.mono(12, .medium))
                .foregroundStyle(Color.white.opacity(0.45))
        }
    }

    private var netRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your net")
                .eyebrow()
            Spacer(minLength: 8)
            Text(Points.format(net, signed: true))
                .font(Theme.mono(18, .semibold))
                .foregroundStyle(netColor)
        }
    }
}
