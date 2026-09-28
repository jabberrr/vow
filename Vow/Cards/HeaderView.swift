import SwiftUI

struct HeaderView: View {
    let cycle: Int
    let day: Int

    private var cycleText: String {
        "Cycle " + String(format: "%02d", cycle)
    }

    private var dayText: String {
        "Day \(day) / \(VowStore.cycleLength)"
    }

    var body: some View {
        HStack(alignment: .center) {
            Text("Vow")
                .font(Theme.display(30, .heavy))
                .gradientText()
            Spacer(minLength: 12)
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
        .frame(height: 44)
        .padding(.horizontal, 4)
    }
}
