import SwiftUI

/// View-layer status. MemberStatus.label is no longer shown anywhere.
enum TodayStatus: Equatable {
    case yourTurn, checkedIn, notYet, missedYesterday, notJoined

    init(_ status: MemberStatus) {
        switch status {
        case .checkedIn: self = .checkedIn
        case .yourMove: self = .yourTurn
        case .notYet: self = .notYet
        case .missed: self = .missedYesterday
        }
    }

    var title: String {
        switch self {
        case .yourTurn: return "Your turn"
        case .checkedIn: return "Checked in"
        case .notYet: return "Not yet"
        case .missedYesterday: return "Missed yesterday"
        case .notJoined: return "Set your vow to join"
        }
    }

    var tint: Color {
        switch self {
        case .yourTurn: return Palette.accent
        case .checkedIn: return Palette.kept
        case .notYet: return Palette.text3
        case .missedYesterday: return Palette.loss
        case .notJoined: return Palette.text2
        }
    }

    var symbol: String? {
        self == .checkedIn ? "checkmark" : nil
    }
}

/// Status word in its colour, with a bold checkmark when checked in.
struct StatusText: View {
    let status: TodayStatus

    init(_ status: TodayStatus) {
        self.status = status
    }

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = status.symbol {
                Image(systemName: symbol)
                    .fontWeight(.bold)
            }
            Text(status.title)
        }
        .font(Typeface.footnoteSemibold)
        .foregroundStyle(status.tint)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.title)
    }
}

/// Small tag ("Test"): caption text in `tint` on a 14% tint rounded rectangle. Never truncates.
struct Chip: View {
    let text: String
    let tint: Color

    init(_ text: String, tint: Color = Palette.warn) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(Typeface.caption)
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }
}
