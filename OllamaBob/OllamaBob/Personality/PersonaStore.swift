import Foundation
import Combine

/// In-memory persona store. Phase 1 Step 1.2a placeholder — the GRDB-backed
/// version with a real `personas` table, user copies, and edit history lands
/// in Step 1.2b along with the Preferences → Personas tab.
///
/// Today this just serves the built-in presets and remembers which one the
/// user last selected via UserDefaults. No custom personas, no editing.
@MainActor
final class PersonaStore: ObservableObject {

    static let shared = PersonaStore()

    /// All known personas. Built-ins only in this substep.
    @Published private(set) var personas: [Persona]

    /// ID of the currently-active persona. On first install this defaults
    /// to Mumbai Bob so v1 behavior is preserved until the onboarding flow
    /// (Step 1.2c) forces the user to pick one.
    @Published var activePersonaID: String {
        didSet { UserDefaults.standard.set(activePersonaID, forKey: Keys.activePersonaID) }
    }

    /// The resolved active persona object. Falls back to Mumbai Bob if the
    /// stored ID has somehow been orphaned (e.g. a future preset removal).
    var activePersona: Persona {
        personas.first(where: { $0.id == activePersonaID }) ?? BuiltinPersonas.mumbaiBob
    }

    private enum Keys {
        static let activePersonaID = "activePersonaID"
    }

    private init() {
        self.personas = BuiltinPersonas.all

        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Keys.activePersonaID),
           BuiltinPersonas.all.contains(where: { $0.id == stored }) {
            self.activePersonaID = stored
        } else {
            // First-launch stopgap: ship with Mumbai Bob active so v1 users
            // notice zero behavior change. Onboarding (Step 1.2c) will clear
            // this and force an explicit pick on fresh installs.
            self.activePersonaID = BuiltinPersonas.mumbaiBobID
        }
    }
}
