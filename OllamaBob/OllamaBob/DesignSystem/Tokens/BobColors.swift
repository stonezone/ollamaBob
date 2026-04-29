import SwiftUI

/// Semantic color palette. Replaces scattered RGB literals across the app.
/// All colors adapt to light/dark via SwiftUI's automatic color scheme support;
/// persona accents are driven by the active `Persona`'s palette and applied
/// at the surface level via `BobColors.PersonaScope`.
@MainActor
enum BobColors {

    enum Surface {
        /// App-canvas neutral. Used by non-glass backgrounds (legacy Sonoma fallback).
        static let canvas = Color(nsColor: .windowBackgroundColor)
        /// Raised surface inside a window (cards, panels behind glass).
        static let raised = Color(nsColor: .underPageBackgroundColor)
        /// Subtle hairline divider matching system separators.
        static let divider = Color(nsColor: .separatorColor)
    }

    enum Glass {
        /// Default frosted-glass tint applied on top of vibrancy materials.
        static let fill = Color.white.opacity(0.08)
        /// Inner-highlight stroke that sells the "glass edge" feeling.
        static let strokeHighlight = Color.white.opacity(0.18)
        /// Outer hairline stroke separating glass from background.
        static let strokeOutline = Color.black.opacity(0.18)
        /// Inset top highlight for a Liquid Glass surface (1pt).
        static let topRimHighlight = Color.white.opacity(0.30)
    }

    enum Text {
        static let primary = Color(nsColor: .labelColor)
        static let secondary = Color(nsColor: .secondaryLabelColor)
        static let tertiary = Color(nsColor: .tertiaryLabelColor)
        /// On-glass text — slightly more opaque than `.primary` to survive
        /// blurred/bright backgrounds.
        static let onGlass = Color.white.opacity(0.92)
        static let onGlassSecondary = Color.white.opacity(0.62)
    }

    enum Accent {
        /// System accent — follows user's macOS accent color.
        static let primary = Color(nsColor: .controlAccentColor)
        /// Tahoe-default cool blue for Bob's signature accent when not
        /// using user accent. Persona override flows through `personaAccent`.
        static let bobBlue = Color(red: 0.37, green: 0.62, blue: 1.00)
    }

    enum Signal {
        static let success = Color(red: 0.30, green: 0.85, blue: 0.39)
        static let warn = Color(red: 1.00, green: 0.74, blue: 0.18)
        static let danger = Color(red: 1.00, green: 0.37, blue: 0.34)
        /// Indeterminate-processing signal. Cooler than `.warn`.
        static let processing = Color(red: 0.40, green: 0.74, blue: 1.00)
    }

    enum Persona {
        /// Phosphor-green Classic Robot signature.
        static let classicRobotPhosphor = Color(red: 0.22, green: 1.00, blue: 0.08)
        /// Mumbai Bob warm-amber base hue.
        static let mumbaiAmber = Color(red: 0.96, green: 0.62, blue: 0.32)
    }

    /// Resolves a persona's accent color into a SwiftUI `Color` usable in
    /// modifiers like `.tint(_:)` or `.foregroundStyle(_:)`. Falls back to
    /// `Accent.bobBlue` when the persona declares no accent override.
    static func personaAccent(_ palette: PersonaPaletteResolving?) -> Color {
        palette?.accentColor ?? Accent.bobBlue
    }
}

/// Adapter so `BobColors.personaAccent(_:)` can resolve a palette without
/// importing the full `Persona` module. The `PersonaPalette` type (Phase 2)
/// will conform to this.
protocol PersonaPaletteResolving {
    var accentColor: Color { get }
}
