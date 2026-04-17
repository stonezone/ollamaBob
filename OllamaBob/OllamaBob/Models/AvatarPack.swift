import Foundation
import AppKit

/// A named bundle of six mood sprites — idle, thinking, typing, happy,
/// sheepish, confused — rendered in a consistent art style. Different
/// packs let the user re-skin Bob to match their persona/mood without
/// forcing one visual identity on everyone.
///
/// Sprites live flat under `Resources/Avatars/` with a pack-unique
/// `filePrefix`, because SPM's `.process(...)` flattens subdirectories —
/// the prefix is how we keep two packs from colliding. For legacy
/// compatibility, the classic pack keeps its files at `Resources/Bob/*`
/// with prefix `bob_`, since `.process` already flattens them to the
/// bundle root.
struct AvatarPack: Identifiable, Hashable, Sendable {
    /// Stable id persisted in UserDefaults.
    let id: String

    /// Human-readable label for the picker.
    let name: String

    /// One-liner shown under the name in the picker.
    let summary: String

    /// Prefix prepended to the mood name to form the PNG lookup.
    /// e.g. `"bob_"` + `"idle"` → `bob_idle.png`.
    let filePrefix: String

    /// Look up the NSImage for a mood. Tries the Asset Catalog first
    /// (classic pack is in Assets.xcassets), then the flat resource bundle.
    @MainActor
    func image(for mood: BobMood) -> NSImage? {
        let name = "\(filePrefix)\(mood.rawValue)"
        if let img = NSImage(named: name) { return img }
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }
}

/// Static catalog of bundled avatar packs. Users can't add their own yet —
/// that's a future feature — but adding a new pack is: drop 6 PNGs with
/// a unique prefix under `Resources/Avatars/`, then append one entry here.
enum AvatarPacks {

    /// The original phosphor-green android. Ships with every build.
    static let classicRobot = AvatarPack(
        id: "classic-robot",
        name: "Classic Robot",
        summary: "The original phosphor-green android.",
        filePrefix: "bob_"
    )

    /// Cartoon "Mumbai Bob" — cheerful young man in a blue polo, rendered
    /// consistently via Gemini 2.5 Flash Image (Nano Banana). Designed to
    /// pair with the Mumbai Bob persona voice.
    static let mumbaiBob = AvatarPack(
        id: "mumbai-bob",
        name: "Mumbai Bob",
        summary: "Cheerful cartoon assistant, pairs with the Mumbai Bob persona.",
        filePrefix: "mumbai_"
    )

    /// Ordered list shown in the picker.
    static let all: [AvatarPack] = [classicRobot, mumbaiBob]

    /// Look up a pack by id, falling back to classic if nothing matches.
    /// Keeps the UI from breaking if a stored pack id is ever removed.
    static func byId(_ id: String) -> AvatarPack {
        all.first(where: { $0.id == id }) ?? classicRobot
    }

    /// Default pack for a given persona when "follow persona" is on.
    /// Only the built-in personas with a clear visual identity get mapped;
    /// everything else falls through to classic-robot.
    static func defaultForPersona(_ personaID: String) -> AvatarPack {
        switch personaID {
        case BuiltinPersonas.mumbaiBobID: return mumbaiBob
        default:                          return classicRobot
        }
    }
}
