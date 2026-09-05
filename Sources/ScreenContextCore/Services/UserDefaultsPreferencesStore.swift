import Foundation

public actor UserDefaultsPreferencesStore: PreferencesStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "ContextCast.Preferences.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> PreferencesSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(PreferencesSnapshot.self, from: data) else {
            return .defaults
        }
        return snapshot.sanitizedForPersistence
    }

    public func save(_ snapshot: PreferencesSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot.sanitizedForPersistence) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
