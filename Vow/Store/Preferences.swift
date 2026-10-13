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
    static let reminderOnKey: String = "vow.reminder.on"
    static let reminderMinuteKey: String = "vow.reminder.minute"
    static let reminderAskedKey: String = "vow.reminder.asked"
    static let revealDayKey: String = "vow.revealDay"
    static let lastVowKey: String = "vow.lastVow"

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

    func loadReminderOn() -> Bool {
        return defaults.bool(forKey: Preferences.reminderOnKey)
    }

    func saveReminderOn(_ on: Bool) {
        defaults.set(on, forKey: Preferences.reminderOnKey)
    }

    /// Minutes after local midnight; ReminderPlan.defaultMinute (20:00) when never set.
    func loadReminderMinute() -> Int {
        guard defaults.object(forKey: Preferences.reminderMinuteKey) != nil else {
            return ReminderPlan.defaultMinute
        }
        return defaults.integer(forKey: Preferences.reminderMinuteKey)
    }

    func saveReminderMinute(_ minute: Int) {
        defaults.set(minute, forKey: Preferences.reminderMinuteKey)
    }

    func loadReminderAsked() -> Bool {
        return defaults.bool(forKey: Preferences.reminderAskedKey)
    }

    func saveReminderAsked(_ asked: Bool) {
        defaults.set(asked, forKey: Preferences.reminderAskedKey)
    }

    /// "yyyy-MM-dd" of the last local day the balance change was revealed.
    func loadRevealDay() -> String? {
        return defaults.string(forKey: Preferences.revealDayKey)
    }

    func saveRevealDay(_ day: String) {
        defaults.set(day, forKey: Preferences.revealDayKey)
    }

    /// zoneName of the vow last shown on the stage.
    func loadLastVowZone() -> String? {
        return defaults.string(forKey: Preferences.lastVowKey)
    }

    func saveLastVowZone(_ zone: String) {
        defaults.set(zone, forKey: Preferences.lastVowKey)
    }

    func clearAll() {
        defaults.removeObject(forKey: Preferences.profileKey)
        defaults.removeObject(forKey: Preferences.testingModeKey)
        defaults.removeObject(forKey: Preferences.userIDKey)
        defaults.removeObject(forKey: Preferences.reminderOnKey)
        defaults.removeObject(forKey: Preferences.reminderMinuteKey)
        defaults.removeObject(forKey: Preferences.reminderAskedKey)
        defaults.removeObject(forKey: Preferences.revealDayKey)
        defaults.removeObject(forKey: Preferences.lastVowKey)
        // Legacy single-player prototype state.
        defaults.removeObject(forKey: "vow.state.v1")
    }
}
