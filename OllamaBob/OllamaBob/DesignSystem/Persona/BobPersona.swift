import SwiftUI

/// Pluggable visual identity for Bob. Renders the abstract glyph (HUD +
/// popover surfaces) and the live character (Bob's Desk pane), declares the
/// palette token consumers will tint surfaces with, and reports which moods
/// it knows how to draw so the renderer can fall back to `.idle` for ones
/// outside its vocabulary.
///
/// Distinct from the conversational `Persona` (`Personality/Persona.swift`)
/// — that struct controls Bob's *voice* (system prompt, tone). `BobPersona`
/// controls Bob's *appearance* (glyph, character, palette, bubble tint).
/// The two systems intentionally stay decoupled: the user can pair any
/// conversational persona with any visual persona.
@MainActor
protocol BobPersona: Identifiable {
    /// Stable identifier persisted in UserDefaults.
    var id: String { get }
    /// Human-readable label for pickers.
    var displayName: String { get }
    /// One-liner shown under the name in the picker.
    var summary: String { get }
    /// Color tokens this persona contributes to surfaces.
    var palette: BobPersonaPalette { get }
    /// Moods this persona has explicit art for. Renderer falls back to
    /// `.idle` for any mood outside this set.
    var moodVocabulary: Set<BobPersonaMood> { get }
    /// Optional voice pack id for matching speech audio. Phase 2 surfaces
    /// this; later phases route TTS through it.
    var voicePackID: String? { get }

    /// Render the abstract HUD/popover glyph at the supplied size + state.
    /// Default implementation provided in the extension below — most
    /// personas only customize tint, not the glyph shape.
    func glyph(state: GlassGlyph.State, size: CGFloat) -> AnyView

    /// Render the live character for Bob's Desk. `gaze` is a normalized
    /// 0-to-1 point inside the rendering frame the character should look
    /// toward (eyes track; nil = forward gaze).
    func character(expression: BobPersonaExpression, gaze: CGPoint?, size: CGFloat) -> AnyView
}

extension BobPersona {
    /// Default glyph: the universal `GlassGlyph` tinted by the persona's
    /// accent color. Personas that want a fully custom mark can override.
    func glyph(state: GlassGlyph.State, size: CGFloat) -> AnyView {
        AnyView(GlassGlyph(state: state, tint: palette.accentColor, size: size))
    }
}

/// Mood vocabulary covering everything the renderer might ask a persona
/// to express. Most map 1:1 from `BobMood` (the chat-loop's mood enum);
/// the four extras (`listening`, `speaking`, `error`, `naughty`) cover
/// surfaces beyond the chat transcript.
enum BobPersonaMood: String, CaseIterable, Hashable {
    case idle, thinking, typing, happy, sheepish, confused
    case listening, speaking, error, naughty

    /// Lift the existing chat-loop `BobMood` into the wider persona vocabulary.
    init(_ bobMood: BobMood) {
        switch bobMood {
        case .idle:      self = .idle
        case .thinking:  self = .thinking
        case .typing:    self = .typing
        case .happy:     self = .happy
        case .sheepish:  self = .sheepish
        case .confused:  self = .confused
        }
    }
}

/// One frame of expression. `intensity` lets the renderer modulate a mood
/// (a faint smile vs a beaming grin) without inventing new mood cases.
struct BobPersonaExpression: Equatable {
    var mood: BobPersonaMood
    var intensity: Double

    init(_ mood: BobPersonaMood, intensity: Double = 1.0) {
        self.mood = mood
        self.intensity = max(0, min(1, intensity))
    }
}

/// Color tokens a persona contributes. Conforms to `PersonaPaletteResolving`
/// so `BobColors.personaAccent(_:)` accepts it directly.
struct BobPersonaPalette: PersonaPaletteResolving {
    /// Primary accent — feeds button fills, glyph tint, bubble tail color.
    var accentColor: Color
    /// Inner-glyph fill color (the orb at the center of `GlassGlyph`).
    var glyphFill: Color
    /// Outer ring/stroke color used by the glyph and character outlines.
    var glyphStroke: Color
    /// Tint applied to user-side bubble glass for this persona.
    var bubbleTint: Color
    /// Base hues the character renderer composes (skin/clothing/accents).
    /// Order matters: `[primary, secondary, accent, ...]`.
    var characterBaseHues: [Color]
}
