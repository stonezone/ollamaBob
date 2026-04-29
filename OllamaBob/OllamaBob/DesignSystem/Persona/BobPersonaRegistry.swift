import Foundation
import Combine

/// Singleton registry of visual personas. Replaces the old
/// `AvatarStore` + `AvatarPack` pair. Personas register themselves at
/// app launch (`OllamaBobApp.init`); renderers ask the registry for the
/// active persona instead of referencing a hard-coded enum or asset name.
///
/// Persistence: the active persona id is stored in UserDefaults under
/// `bobPersona.activeID`. If a stored id no longer matches a registered
/// persona (a build dropped one), the registry silently falls back to the
/// first persona in registration order.
@MainActor
final class BobPersonaRegistry: ObservableObject {

    static let shared = BobPersonaRegistry()

    /// Registered personas in the order they were added. UI pickers iterate
    /// this list to render the persona-swap menu.
    @Published private(set) var personas: [any BobPersona] = []

    /// Stable id of the currently active persona. Mutating publishes a
    /// change so SwiftUI views observing the registry re-render.
    @Published var activeID: String {
        didSet { UserDefaults.standard.set(activeID, forKey: Keys.activeID) }
    }

    /// The currently active persona. Falls back to the first registered
    /// persona if the stored id has gone stale.
    var active: any BobPersona {
        if let match = personas.first(where: { $0.id == activeID }) { return match }
        if let first = personas.first { return first }
        // Nothing registered yet — the renderer should never reach here in
        // production because `OllamaBobApp.init` registers built-ins before
        // any view appears. Surface the gap loudly in debug builds.
        preconditionFailure("BobPersonaRegistry has no registered personas")
    }

    /// Register a persona. Idempotent on `id`: registering the same id
    /// twice replaces the earlier entry rather than duplicating it. Order
    /// of first registration is preserved so the picker stays stable.
    func register(_ persona: any BobPersona) {
        if let index = personas.firstIndex(where: { $0.id == persona.id }) {
            personas[index] = persona
        } else {
            personas.append(persona)
        }
        // If nothing's active yet (or the stored id doesn't match anything),
        // make this the active one so first launch lands on a real persona.
        if personas.first(where: { $0.id == activeID }) == nil {
            activeID = persona.id
        }
    }

    /// Look up a persona by id without mutating the active selection.
    func persona(withID id: String) -> (any BobPersona)? {
        personas.first(where: { $0.id == id })
    }

    /// Set the active persona by id. No-op if the id isn't registered.
    func setActive(_ id: String) {
        guard personas.contains(where: { $0.id == id }) else { return }
        activeID = id
    }

    private enum Keys {
        static let activeID = "bobPersona.activeID"
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Keys.activeID) ?? ""
        self.activeID = stored
    }
}
