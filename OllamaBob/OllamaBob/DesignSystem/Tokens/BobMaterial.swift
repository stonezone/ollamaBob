import SwiftUI
import AppKit

/// Vibrancy material vocabulary. Maps semantic surface roles to either
/// SwiftUI `Material` (legacy, macOS 14+) or `glassEffect` (macOS 26+ Tahoe).
/// Reduce-Transparency-aware: collapses to solid surface tokens.
@MainActor
enum BobMaterial {
    /// Surface role drives material thickness, tint, and shape preset.
    enum Role {
        case popover         // menu-bar dropdown
        case deskWindow      // full chat window background
        case hud             // floating chrome-less HUD
        case bubble          // standard speech bubble
        case bubbleEmphasized // user/highlighted bubble
    }

    /// Resolves the legacy SwiftUI `Material` for a role on macOS pre-Tahoe
    /// or when Reduce Transparency is active. Always safe to call.
    static func legacyMaterial(for role: Role) -> Material {
        switch role {
        case .popover, .hud:        return .ultraThinMaterial
        case .deskWindow:           return .thinMaterial
        case .bubble:               return .regularMaterial
        case .bubbleEmphasized:     return .thickMaterial
        }
    }

    /// Solid fallback color when Reduce Transparency is enabled. Maps each
    /// role to a token-driven opaque surface so glass collapses to a flat
    /// readable background.
    static func reducedTransparencyFill(for role: Role) -> Color {
        switch role {
        case .popover, .hud:        return BobColors.Surface.raised
        case .deskWindow:           return BobColors.Surface.canvas
        case .bubble:               return BobColors.Surface.raised.opacity(0.92)
        case .bubbleEmphasized:     return BobColors.Accent.bobBlue.opacity(0.30)
        }
    }

    /// Native `NSVisualEffectView.Material` for cases where AppKit-level
    /// vibrancy is required (e.g. window backgrounds via `NSWindow`).
    static func appKitMaterial(for role: Role) -> NSVisualEffectView.Material {
        switch role {
        case .popover:              return .menu
        case .deskWindow:           return .windowBackground
        case .hud:                  return .hudWindow
        case .bubble:               return .popover
        case .bubbleEmphasized:     return .selection
        }
    }
}
