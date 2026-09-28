import SwiftUI

struct LedgerCard: View {
    /// Newest first (as stored).
    let entries: [LedgerEntry]
    let stake: Stake

    private var visible: [LedgerEntry] {
        Array(entries.prefix(30))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ledger")
                .eyebrow()
            if entries.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var emptyState: some View {
        Text("Nothing yet. Hold the orb to make your first mark.")
            .font(Theme.mono(12, .medium))
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.vertical, 6)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(visible) { entry in
                LedgerRow(entry: entry, stake: stake)
            }
        }
    }
}

private struct LedgerRow: View {
    let entry: LedgerEntry
    let stake: Stake

    private var dayTag: String {
        "D " + String(format: "%02d", entry.day)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(dayTag)
                .font(Theme.mono(11, .semibold))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(width: 38, alignment: .leading)
            Text(entry.text)
                .font(Theme.mono(12, .medium))
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            amount
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var amount: some View {
        if let value = entry.amount {
            Text(stake.format(value, signed: true))
                .font(Theme.mono(12, .semibold))
                .foregroundStyle(value >= 0 ? Theme.lime : Theme.pink)
                .lineLimit(1)
        }
    }
}
