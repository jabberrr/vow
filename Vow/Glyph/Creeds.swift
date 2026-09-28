import Foundation

enum Creeds {
    static let all: [String] = [
        "Small fires, kept daily.",
        "Show up before you feel ready.",
        "The streak is the sermon.",
        "Do the rep. Seal the day.",
        "Nobody's watching. Do it anyway.",
        "Keep the promise. Keep the pot.",
        "Today is the only day that counts.",
        "Discipline is a quiet kind of loud.",
        "Your crew is counting on you.",
        "Begin badly. Finish anyway.",
        "One more day. That's the whole plan.",
        "Motion beats mood.",
        "The vow holds if you do.",
        "Earn the glyph. Light the orb."
    ]

    static func line(for index: Int) -> String {
        let n: Int = all.count
        let i: Int = ((index % n) + n) % n
        return all[i]
    }
}
