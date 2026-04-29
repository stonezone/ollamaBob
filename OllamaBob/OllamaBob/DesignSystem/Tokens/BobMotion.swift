import SwiftUI

/// Motion vocabulary. Curves and durations chosen so the app reads as
/// "macOS-native expressive" rather than "web-app bouncy". All public
/// curves degrade gracefully under Reduce Motion via `respectingReduceMotion`.
@MainActor
enum BobMotion {
    /// Fast UI feedback (hover, focus rings, selection state).
    static let responsive: Animation = .easeOut(duration: 0.18)

    /// Default state-transition curve for content swaps.
    static let standard: Animation = .easeInOut(duration: 0.24)

    /// Spring-loaded transitions for bigger gestures (mode switches, persona swap).
    static let expressive: Animation = .spring(response: 0.32, dampingFraction: 0.78)

    /// Slow loop for idle avatar breath. Always uses `.easeInOut` so the
    /// loop returns smoothly to its origin scale.
    static let breath: Animation = .easeInOut(duration: 3.5).repeatForever(autoreverses: true)

    /// Smoothed eye-tracking curve. Short enough to feel reactive,
    /// long enough to avoid jitter on cursor micro-movements.
    static let gaze: Animation = .easeOut(duration: 0.8)

    /// Returns the supplied animation, or a tiny opacity-only fade when
    /// the user has Reduce Motion enabled.
    static func respectingReduceMotion(
        _ animation: Animation,
        reduceMotion: Bool
    ) -> Animation? {
        reduceMotion ? .easeInOut(duration: 0.12) : animation
    }
}
