import SwiftUI

struct BalanceCard: View {
    let balance: Double
    let groupCount: Int

    private var color: Color {
        balance >= 0 ? Theme.lime : Theme.pink
    }

    private var caption: String {
        if groupCount == 0 {
            return "Points you win and forfeit across your groups"
        }
        return "Across " + (groupCount == 1 ? "1 group" : "\(groupCount) groups") + " · points only"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Balance")
                .eyebrow()
            Text(Points.format(balance, signed: true))
                .font(Theme.mono(40, .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(Theme.mono(12, .medium))
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
