import SwiftUI

/// Cheerful cartoon Mumbai Bob — warm-amber face, blue polo, expressive
/// brows + mouth. Default visual persona. Migrated from a 6-PNG sprite
/// pack to a SwiftUI vector renderer.
struct MumbaiBobPersona: BobPersona {
    let id = "mumbai-bob"
    let displayName = "Mumbai Bob"
    let summary = "Warm cartoon assistant with tracking eyes and a blue polo."
    let voicePackID: String? = "mumbai-bob"

    let palette = BobPersonaPalette(
        accentColor: BobColors.Persona.mumbaiAmber,
        glyphFill: BobColors.Persona.mumbaiAmber.opacity(0.95),
        glyphStroke: Color(red: 0.45, green: 0.22, blue: 0.10),
        bubbleTint: BobColors.Persona.mumbaiAmber.opacity(0.28),
        characterBaseHues: [
            Color(red: 0.99, green: 0.78, blue: 0.55),  // skin highlight
            Color(red: 0.92, green: 0.62, blue: 0.36)   // skin midtone
        ]
    )

    let moodVocabulary: Set<BobPersonaMood> = Set(BobPersonaMood.allCases)

    func character(expression: BobPersonaExpression, gaze: CGPoint?, size: CGFloat) -> AnyView {
        AnyView(
            MumbaiBobCharacterView(
                expression: expression,
                palette: palette,
                gaze: gaze,
                size: size
            )
        )
    }
}
