import SwiftUI

/// One ledger line: kind symbol, text, and the amount in the right column. One VoiceOver element.
/// Your own lines are brighter and your amounts coloured; everyone else's stay grey.
struct LedgerRow: View {
    let line: LedgerLine

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize: DynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var symbolSize: CGFloat = 19

    init(line: LedgerLine) {
        self.line = line
    }

    private var own: Bool {
        LedgerFormat.isOwn(line.kind)
    }

    var body: some View {
        HStack(alignment: .center, spacing: Gap.m) {
            symbol
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Gap.xxs) {
                    text
                    amount
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                text
                Spacer(minLength: Gap.s)
                amount
            }
        }
        .padding(.horizontal, Gap.l)
        .padding(.vertical, Gap.s)
        .frame(minHeight: Gap.hit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LedgerFormat.spoken(line))
    }

    private var symbol: some View {
        Image(systemName: LedgerFormat.symbol(line.kind))
            .font(.system(size: symbolSize, weight: .regular))
            .foregroundStyle(LedgerFormat.tint(line.kind))
            .frame(width: symbolSize + 3)
    }

    private var text: some View {
        Text(LedgerFormat.body(line))
            .font(Fonts.subheadline)
            .foregroundStyle(own ? Ink.text : Ink.text2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var amount: some View {
        if let value: String = LedgerFormat.trailing(line) {
            Text(value)
                .font(Fonts.subheadline)
                .fontWeight(own ? Font.Weight.semibold : Font.Weight.regular)
                .monospacedDigit()
                .foregroundStyle(LedgerFormat.trailingTint(line))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .layoutPriority(1)
        }
    }
}
