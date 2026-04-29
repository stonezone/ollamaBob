import SwiftUI

/// Type scale built on SF Pro / SF Mono with deliberate weight and tracking.
/// Replaces inline `Font.system(...)` calls scattered across views.
@MainActor
enum BobTypography {
    /// Headline typography for empty states, onboarding, hero copy.
    static let display = Font.system(size: 26, weight: .semibold, design: .default)
    /// Section titles within Desk and Preferences panes.
    static let title = Font.system(size: 17, weight: .semibold, design: .default)
    /// Default chat-bubble body text.
    static let body = Font.system(size: 14, weight: .regular, design: .default)
    /// Body text emphasized — speech bubbles in HUD, key call-outs.
    static let bodyEmphasized = Font.system(size: 14, weight: .medium, design: .default)
    /// Mono body text for inline code, command output, deterministic values.
    static let bodyMono = Font.system(size: 13, weight: .regular, design: .monospaced)
    /// Caption used by chips, status pills, metadata.
    static let caption = Font.system(size: 11, weight: .medium, design: .default)
    /// Mono caption for terminal-feel chips and shortcut hints.
    static let captionMono = Font.system(size: 11, weight: .medium, design: .monospaced)
    /// Compact label for popover thread timestamps and tiny metadata.
    static let micro = Font.system(size: 10, weight: .semibold, design: .monospaced)
}
