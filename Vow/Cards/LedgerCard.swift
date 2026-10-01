import SwiftUI

struct LedgerCard: View {
    /// Newest first.
    let lines: [LedgerLine]
    var isTest: Bool = false

    private var visible: [LedgerLine] {
        Array(lines.prefix(40))
    }

    private var emptyText: String {
        if isTest {
            return "Nothing yet. Advance the day to settle it: misses fill the pot, keepers split it."
        }
        return "Nothing yet. Each day settles at midnight: misses fill the pot, keepers split it."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ledger")
                .eyebrow()
            if lines.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var emptyState: some View {
        Text(emptyText)
            .font(Theme.mono(12, .medium))
            .foregroundStyle(Color.white.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(visible) { line in
                LedgerRow(line: line)
            }
        }
    }
}

private struct LedgerRow: View {
    let line: LedgerLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(line.text)
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
        if let value = line.amount {
            Text(Points.format(value, signed: true))
                .font(Theme.mono(12, .semibold))
                .foregroundStyle(value >= 0 ? Theme.lime : Theme.pink)
                .lineLimit(1)
        }
    }
}
