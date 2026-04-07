import Foundation
import Combine

/// Singleton store for user preferences, backed by UserDefaults.
/// Consumed by PreferencesView and AvatarWindow to react to live changes.
@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    @Published var showFloatingAvatar: Bool {
        didSet { UserDefaults.standard.set(showFloatingAvatar, forKey: Keys.showFloatingAvatar) }
    }

    @Published var avatarPersistAcrossSpaces: Bool {
        didSet { UserDefaults.standard.set(avatarPersistAcrossSpaces, forKey: Keys.avatarPersistAcrossSpaces) }
    }

    private enum Keys {
        static let showFloatingAvatar        = "showFloatingAvatar"
        static let avatarPersistAcrossSpaces = "avatarPersistAcrossSpaces"
    }

    private init() {
        let defaults = UserDefaults.standard

        // Write first-launch defaults only when no value exists yet.
        if defaults.object(forKey: Keys.showFloatingAvatar) == nil {
            defaults.set(false, forKey: Keys.showFloatingAvatar)
        }
        if defaults.object(forKey: Keys.avatarPersistAcrossSpaces) == nil {
            defaults.set(true, forKey: Keys.avatarPersistAcrossSpaces)
        }

        self.showFloatingAvatar        = defaults.bool(forKey: Keys.showFloatingAvatar)
        self.avatarPersistAcrossSpaces = defaults.bool(forKey: Keys.avatarPersistAcrossSpaces)
    }
}
