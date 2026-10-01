import Foundation

/// The local user's profile (display name shown to group mates).
struct Profile: Codable, Equatable {
    var displayName: String
}

/// Small UserDefaults-backed settings. Failures are ignored.
struct Preferences {
    static let profileKey: String = "vow.profile"
    static let testingModeKey: String = "vow.testingMode"
    static let userIDKey: String = "vow.userID"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadProfile() -> Profile? {
        guard let data = defaults.data(forKey: Preferences.profileKey) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }

    func saveProfile(_ profile: Profile?) {
        if let p = profile, let data = try? JSONEncoder().encode(p) {
            defaults.set(data, forKey: Preferences.profileKey)
        } else {
            defaults.removeObject(forKey: Preferences.profileKey)
        }
    }

    func loadTestingMode() -> Bool {
        return defaults.bool(forKey: Preferences.testingModeKey)
    }

    func saveTestingMode(_ on: Bool) {
        defaults.set(on, forKey: Preferences.testingModeKey)
    }

    func loadUserID() -> String? {
        return defaults.string(forKey: Preferences.userIDKey)
    }

    func saveUserID(_ id: String?) {
        if let id = id {
            defaults.set(id, forKey: Preferences.userIDKey)
        } else {
            defaults.removeObject(forKey: Preferences.userIDKey)
        }
    }

    func clearAll() {
        defaults.removeObject(forKey: Preferences.profileKey)
        defaults.removeObject(forKey: Preferences.testingModeKey)
        defaults.removeObject(forKey: Preferences.userIDKey)
        // Legacy single-player prototype state.
        defaults.removeObject(forKey: "vow.state.v1")
    }
}
