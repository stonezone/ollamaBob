import Foundation
import Combine

/// Tracks which avatar pack is active and whether it should auto-bind to
/// the current persona. Persisted in UserDefaults so the user's pick
/// survives app restarts.
///
/// Observed by BobsDeskView so picking a new pack or switching persona
/// (with `followPersona` on) re-renders the sprite immediately.
@MainActor
final class AvatarStore: ObservableObject {

    static let shared = AvatarStore()

    /// Manually-selected pack id. Ignored when `followPersona` is true —
    /// that path computes the effective pack from the active persona.
    @Published var activePackID: String {
        didSet { UserDefaults.standard.set(activePackID, forKey: Keys.activePackID) }
    }

    /// When on, the active pack is derived from the active persona via
    /// `AvatarPacks.defaultForPersona`. When off, `activePackID` wins.
    /// Default ON — most users will appreciate Mumbai Bob voice + Mumbai
    /// Bob sprite automatically staying in sync.
    @Published var followPersona: Bool {
        didSet { UserDefaults.standard.set(followPersona, forKey: Keys.followPersona) }
    }

    /// The pack that should actually be rendered right now. Views use
    /// this rather than reading `activePackID` directly so the
    /// follow-persona logic is in one place.
    func effectivePack(activePersonaID: String) -> AvatarPack {
        if followPersona {
            return AvatarPacks.defaultForPersona(activePersonaID)
        }
        return AvatarPacks.byId(activePackID)
    }

    private enum Keys {
        static let activePackID  = "avatar.activePackID"
        static let followPersona = "avatar.followPersona"
    }

    private init() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Keys.activePackID) == nil {
            defaults.set(AvatarPacks.classicRobot.id, forKey: Keys.activePackID)
        }
        if defaults.object(forKey: Keys.followPersona) == nil {
            defaults.set(true, forKey: Keys.followPersona)
        }

        self.activePackID  = defaults.string(forKey: Keys.activePackID) ?? AvatarPacks.classicRobot.id
        self.followPersona = defaults.bool(forKey: Keys.followPersona)
    }
}
