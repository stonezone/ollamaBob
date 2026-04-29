import XCTest
import SwiftUI
@testable import OllamaBob

@MainActor
final class BobPersonaTests: XCTestCase {

    // MARK: - Mood lift from BobMood

    func testBobPersonaMoodMirrorsBobMoodValues() {
        let moods: [(BobMood, BobPersonaMood)] = [
            (.idle,     .idle),
            (.thinking, .thinking),
            (.typing,   .typing),
            (.happy,    .happy),
            (.sheepish, .sheepish),
            (.confused, .confused)
        ]
        for (input, expected) in moods {
            XCTAssertEqual(BobPersonaMood(input), expected, "BobMood.\(input) should lift to BobPersonaMood.\(expected)")
        }
    }

    func testBobPersonaMoodIncludesExtendedVocabulary() {
        // The wider vocabulary is needed by HUD / popover / system surfaces
        // beyond the chat loop's six core moods.
        let extended: Set<BobPersonaMood> = [.listening, .speaking, .error, .naughty]
        XCTAssertTrue(extended.isSubset(of: Set(BobPersonaMood.allCases)))
    }

    // MARK: - Expression intensity clamps

    func testBobPersonaExpressionClampsIntensity() {
        XCTAssertEqual(BobPersonaExpression(.happy, intensity: 2.5).intensity, 1.0)
        XCTAssertEqual(BobPersonaExpression(.happy, intensity: -1.0).intensity, 0.0)
        XCTAssertEqual(BobPersonaExpression(.happy, intensity: 0.4).intensity, 0.4)
    }

    // MARK: - Palette conformance

    func testBobPersonaPaletteResolvesAccentForBobColors() {
        let palette = BobPersonaPalette(
            accentColor: .red,
            glyphFill: .red,
            glyphStroke: .black,
            bubbleTint: .red,
            characterBaseHues: [.red]
        )
        let resolved = BobColors.personaAccent(palette)
        XCTAssertEqual(String(describing: resolved), String(describing: Color.red))
    }

    // MARK: - Registry behavior

    func testRegistryIsIdempotentOnRegister() {
        let registry = BobPersonaRegistry.shared
        let beforeCount = registry.personas.count
        registry.register(MumbaiBobPersona())
        registry.register(MumbaiBobPersona())
        let afterCount = registry.personas.count
        // Registering the same id twice should not duplicate.
        XCTAssertEqual(beforeCount, afterCount)
    }

    func testRegistryActivePersonaResolvesAfterRegistration() {
        let registry = BobPersonaRegistry.shared
        registry.register(MumbaiBobPersona())
        registry.register(ClassicRobotPersona())
        registry.setActive("classic-robot")
        XCTAssertEqual(registry.active.id, "classic-robot")
        registry.setActive("mumbai-bob")
        XCTAssertEqual(registry.active.id, "mumbai-bob")
    }

    func testRegistryFallsBackToFirstWhenActiveIDIsStale() {
        let registry = BobPersonaRegistry.shared
        registry.register(MumbaiBobPersona())
        registry.register(ClassicRobotPersona())
        // setActive only accepts known ids — directly poking activeID with
        // a bogus value simulates "build dropped a persona that was active".
        registry.activeID = "no-such-persona"
        // active should still resolve to *some* persona (the first registered).
        XCTAssertNotNil(registry.persona(withID: registry.active.id))
    }

    func testRegistrySetActiveIgnoresUnknownIDs() {
        let registry = BobPersonaRegistry.shared
        registry.register(MumbaiBobPersona())
        let beforeActive = registry.activeID
        registry.setActive("definitely-not-real")
        XCTAssertEqual(registry.activeID, beforeActive)
    }

    // MARK: - Persona conformance smoke tests

    func testMumbaiBobConformsAndRendersAllVocabularyMoods() {
        let persona = MumbaiBobPersona()
        XCTAssertEqual(persona.id, "mumbai-bob")
        XCTAssertEqual(persona.moodVocabulary, Set(BobPersonaMood.allCases))
        for mood in persona.moodVocabulary {
            let view = persona.character(
                expression: BobPersonaExpression(mood),
                gaze: nil,
                size: 80
            )
            // Just exercises the AnyView pipeline without trapping.
            XCTAssertNotNil(view)
        }
    }

    func testClassicRobotConformsAndDeclaresMoodGap() {
        let persona = ClassicRobotPersona()
        XCTAssertEqual(persona.id, "classic-robot")
        // Naughty is intentionally outside Classic Robot's vocabulary; the
        // renderer should fall back at the call site.
        XCTAssertFalse(persona.moodVocabulary.contains(.naughty))
        XCTAssertTrue(persona.moodVocabulary.contains(.idle))
    }

    func testGlyphDefaultImplementationProducesView() {
        let persona = MumbaiBobPersona()
        let glyph = persona.glyph(state: .idle, size: 32)
        XCTAssertNotNil(glyph)
    }

    // MARK: - Gaze handling

    func testCharacterRendererAcceptsGazePoint() {
        let persona = MumbaiBobPersona()
        let view = persona.character(
            expression: BobPersonaExpression(.idle),
            gaze: CGPoint(x: 0.7, y: 0.3),
            size: 100
        )
        XCTAssertNotNil(view)
    }
}
