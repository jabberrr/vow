import Foundation

/// All amounts are points (Double), shown like "5 pts", "0.67 pts", "+1.33 pts", "−2 pts".
enum Points {
    static let stakeOptions: [Int] = [1, 2, 5, 10]

    /// At most 2 decimals with trailing zeros trimmed. Negative values use the Unicode minus "−";
    /// `signed` adds "+" to non-negative values (including zero: "+0 pts").
    static func format(_ v: Double, signed: Bool = false) -> String {
        let mag: Double = abs(v)
        let rounded: Double = (mag * 100).rounded() / 100
        let isZero: Bool = rounded == 0
        var body: String = String(format: "%.2f", rounded)
        if body.contains(".") {
            while body.hasSuffix("0") {
                body.removeLast()
            }
            if body.hasSuffix(".") {
                body.removeLast()
            }
        }
        let sign: String
        if v < 0 && !isZero {
            sign = "\u{2212}"
        } else if signed {
            sign = "+"
        } else {
            sign = ""
        }
        return sign + body + " pts"
    }
}
