import SwiftUI

/// Phosphor-green android, the original Bob. Migrated from a 6-PNG sprite
/// pack to a SwiftUI vector renderer. Glyph reuses the universal
/// `GlassGlyph` tinted phosphor-green; the live character is in
/// `ClassicRobotCharacterView`.
struct ClassicRobotPersona: BobPersona {
    let id = "classic-robot"
    let displayName = "Classic Robot"
    let summary = "Phosphor-green android — Bob's original look, now drawn live."
    let voicePackID: String? = nil

    let palette = BobPersonaPalette(
        accentColor: BobColors.Persona.classicRobotPhosphor,
        glyphFill: BobColors.Persona.classicRobotPhosphor.opacity(0.95),
        glyphStroke: BobColors.Persona.classicRobotPhosphor.opacity(0.5),
        bubbleTint: BobColors.Persona.classicRobotPhosphor.opacity(0.30),
        characterBaseHues: [
            Color(red: 0.10, green: 0.18, blue: 0.10),
            Color(red: 0.08, green: 0.14, blue: 0.08)
        ]
    )

    let moodVocabulary: Set<BobPersonaMood> = [
        .idle, .thinking, .typing, .happy, .sheepish, .confused,
        .listening, .speaking, .error
        // .naughty intentionally absent — falls back to .confused.
    ]

    func character(expression: BobPersonaExpression, gaze: CGPoint?, size: CGFloat) -> AnyView {
        AnyView(
            ClassicRobotCharacterView(
                expression: expression,
                palette: palette,
                gaze: gaze,
                size: size
            )
        )
    }
}
