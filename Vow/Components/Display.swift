import SwiftUI

/// Round avatar on Palette.raised. The viewer gets a person glyph; others their initial ("?" if empty).
/// Decorative: rows carry their own accessibility label.
struct Avatar: View {
    let name: String
    let isViewer: Bool
    let size: CGFloat

    init(name: String, isViewer: Bool = false, size: CGFloat = 36) {
        self.name = name
        self.isViewer = isViewer
        self.size = size
    }

    private var initial: String {
        let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Palette.raised)
            Circle()
                .strokeBorder(Palette.hairline, lineWidth: 1)
            glyph
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        if isViewer {
            Image(systemName: "person.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.text2)
        } else {
            Text(initial)
                .font(Typeface.subheadlineSemibold)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(4)
        }
    }
}

/// Section title at the gutter with an optional trailing note. Callers put 10pt between it and the card below.
struct SectionHeader: View {
    let title: String
    let trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Typeface.subheadlineSemibold)
                .foregroundStyle(Palette.text2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing = trailing {
                Text(trailing)
                    .font(Typeface.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.text3)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

/// Number + unit over a label ("2 pts / Daily stake"). VoiceOver: "Daily stake, 2 points".
struct StatView: View {
    let number: String
    let unit: String
    let label: String
    let tint: Color

    init(number: String, unit: String, label: String, tint: Color = Palette.text) {
        self.number = number
        self.unit = unit
        self.label = label
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            figure
            Text(label)
                .font(Typeface.footnote)
                .foregroundStyle(Palette.text2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue)
    }

    private var figure: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(number)
                .font(Typeface.stat)
                .monospacedDigit()
                .foregroundStyle(tint)
            if !unit.isEmpty {
                Text(unit)
                    .font(Typeface.statUnit)
                    .foregroundStyle(Palette.text2)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// "+4.5" "pts" -> "plus 4.5 points"; "1" "pt" -> "1 point".
    private var spokenValue: String {
        var magnitude: String = number
        var prefix: String = ""
        if number.hasPrefix("+") {
            prefix = "plus "
            magnitude = String(number.dropFirst())
        } else if number.hasPrefix("\u{2212}") || number.hasPrefix("-") {
            prefix = "minus "
            magnitude = String(number.dropFirst())
        }
        let spokenUnit: String
        switch unit {
        case "pts", "pt":
            spokenUnit = magnitude == "1" ? " point" : " points"
        case "":
            spokenUnit = ""
        default:
            spokenUnit = " " + unit
        }
        return prefix + magnitude + spokenUnit
    }
}

/// Balance hero: signed rounded numeral in the points colour (white at zero) with a "pts" unit.
/// The numeral rolls when the value changes.
struct HeroNumber: View {
    let value: Double
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 46

    init(value: Double) {
        self.value = value
    }

    private var parts: (number: String, unit: String) {
        PointsText.parts(value, signed: true)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            numeral
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(Typeface.heroUnit)
                    .foregroundStyle(Palette.text2)
                    .lineLimit(1)
            }
        }
        .animation(Motion.standard, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PointsText.spoken(value, signed: true))
    }

    private var numeral: some View {
        Text(parts.number)
            .font(Font.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Palette.points(value, zero: Palette.text))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText(value: value))
    }
}

/// Inline problem row in its own card: warn icon, message, accent action (44pt tall target).
struct Banner: View {
    let systemImage: String
    let text: String
    let actionTitle: String
    let action: () -> Void

    init(systemImage: String, text: String, actionTitle: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Palette.warn)
                .accessibilityHidden(true)
            Text(text)
                .font(Typeface.subheadline)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            actionButton
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var actionButton: some View {
        Button(action: action) {
            Text(actionTitle)
                .font(Typeface.subheadlineSemibold)
                .foregroundStyle(Palette.accent)
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: Space.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(Palette.accent)
    }
}

/// Points formatting for display and VoiceOver.
enum PointsText {
    /// Points.format split: "+1.33 pts" -> ("+1.33", "pts"), "+1 pts" -> ("+1", "pt").
    /// If the suffix " pts" is missing: (full, "").
    static func parts(_ value: Double, signed: Bool = false) -> (number: String, unit: String) {
        let full: String = Points.format(value, signed: signed)
        guard full.hasSuffix(" pts") else {
            return (number: full, unit: "")
        }
        let number: String = String(full.dropLast(4))
        let magnitude: String = number.trimmingCharacters(in: CharacterSet(charactersIn: "+\u{2212}"))
        return (number: number, unit: magnitude == "1" ? "pt" : "pts")
    }

    /// Points.format with a singular unit for exactly one point: "+1 pt", "5 pts".
    static func string(_ value: Double, signed: Bool = false) -> String {
        let split: (number: String, unit: String) = PointsText.parts(value, signed: signed)
        return split.unit.isEmpty ? split.number : split.number + " " + split.unit
    }

    /// VoiceOver: "plus 1.33 points", "minus 2 points", "0 points", "plus 1 point".
    static func spoken(_ value: Double, signed: Bool = false) -> String {
        let number: String = PointsText.parts(value, signed: signed).number
        var magnitude: String = number
        var prefix: String = ""
        if number.hasPrefix("+") {
            prefix = "plus "
            magnitude = String(number.dropFirst())
        } else if number.hasPrefix("\u{2212}") {
            prefix = "minus "
            magnitude = String(number.dropFirst())
        }
        let unit: String = magnitude == "1" ? "point" : "points"
        return prefix + magnitude + " " + unit
    }
}
