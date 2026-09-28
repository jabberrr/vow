import Foundation

/// UserDefaults-backed JSON persistence for VowState.
struct Persistence {
    static let key: String = "vow.state.v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> VowState? {
        guard let data = defaults.data(forKey: Persistence.key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(VowState.self, from: data)
    }

    func save(_ state: VowState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) {
            defaults.set(data, forKey: Persistence.key)
        }
    }

    func clear() {
        defaults.removeObject(forKey: Persistence.key)
    }
}
