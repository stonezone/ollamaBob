import AppKit
import AVFoundation
import Foundation

/// Pre-rendered ElevenLabs voice clips of Mumbai Bob. The full catalog is
/// bundled at build time from Resources/BobSayings/manifest.json. We pick a
/// random clip from the requested category and play it with AVAudioPlayer so
/// it survives being re-triggered before the previous clip finishes.
@MainActor
enum BobSayings {

    enum Category: String {
        case greeting
        case boast
        case celebration
        case working
        case idleReturn = "idle_return"
        case goodbye
    }

    private struct ManifestEntry: Decodable {
        let category: String
        let hash: String
        let text: String
        let file: String
    }

    private struct Manifest: Decodable {
        let voiceId: String
        let entries: [ManifestEntry]

        enum CodingKeys: String, CodingKey {
            case voiceId = "voice_id"
            case entries
        }
    }

    // Cached manifest grouped by category → list of bundle URLs
    private static let catalog: [String: [URL]] = loadCatalog()

    // Hold on to the currently-playing player so ARC doesn't kill it mid-clip.
    private static var activePlayer: AVAudioPlayer?

    /// Play a random clip from the category. Silent no-op if:
    ///   • master sounds or Bob-voice toggles are off,
    ///   • the active persona isn't Mumbai Bob (voice doesn't match others),
    ///   • the category has no clips bundled.
    static func play(_ category: Category) {
        let settings = AppSettings.shared
        guard settings.soundsEnabled, settings.bobVoiceEnabled else { return }
        guard PersonaStore.shared.activePersonaID == BuiltinPersonas.mumbaiBobID else { return }
        guard let url = catalog[category.rawValue]?.randomElement() else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            activePlayer = player
        } catch {
            // Silent — a voice clip failing to load shouldn't disrupt the UI.
        }
    }

    // MARK: - Loading

    private static func loadCatalog() -> [String: [URL]] {
        // SPM's .process() flattens Resources/BobSayings/* into the bundle
        // root, so lookups don't use a subdirectory.
        guard let manifestURL = Bundle.module.url(
            forResource: "manifest",
            withExtension: "json"
        ) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)

            var byCategory: [String: [URL]] = [:]
            for entry in manifest.entries {
                let name = (entry.file as NSString).deletingPathExtension
                guard let url = Bundle.module.url(
                    forResource: name,
                    withExtension: "mp3"
                ) else { continue }
                byCategory[entry.category, default: []].append(url)
            }
            return byCategory
        } catch {
            return [:]
        }
    }
}
