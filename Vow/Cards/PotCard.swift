import SwiftUI

struct PotCard: View {
    let stake: Stake
    let cyclePot: Double
    let pot: Double
    let net: Double

    private var netColor: Color {
        net >= 0 ? Theme.lime : Theme.pink
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pot · this cycle")
                .eyebrow()
            Text(stake.format(cyclePot))
                .font(Theme.mono(36, .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if pot > 0 {
                Text("Carrying " + stake.format(pot) + " · nobody kept")
                    .font(Theme.mono(12, .medium))
                    .foregroundStyle(Theme.amber)
            }
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            netRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var netRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your net")
                .eyebrow()
            Spacer(minLength: 8)
            Text(stake.format(net, signed: true))
                .font(Theme.mono(18, .semibold))
                .foregroundStyle(netColor)
        }
    }
}
