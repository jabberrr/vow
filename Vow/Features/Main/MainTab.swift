import Foundation

/// The selected group's five pages, in tab-bar order.
enum MainTab: Int, CaseIterable, Identifiable {
    case home
    case chat
    case streak
    case activity
    case group

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .chat: return "Chat"
        case .streak: return "Streak"
        case .activity: return "Activity"
        case .group: return "Group"
        }
    }

    /// Unselected symbol. Selected tabs (and a lit Streak tab) use `selectedSymbol`.
    var symbol: String {
        switch self {
        case .home: return "house"
        case .chat: return "bubble.left.and.bubble.right"
        case .streak: return "flame"
        case .activity: return "list.bullet.rectangle"
        case .group: return "person.2"
        }
    }

    var selectedSymbol: String {
        symbol + ".fill"
    }
}
