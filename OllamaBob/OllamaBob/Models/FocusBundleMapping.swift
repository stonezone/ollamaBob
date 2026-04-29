import Foundation

/// Maps macOS bundle identifiers to persona IDs.
///
/// `FocusBundleMapping` owns the built-in defaults and merges them with any
/// user overrides stored in `AppSettings.focusGuardianOverrides`. User values
/// win on collision.
struct FocusBundleMapping {

    // MARK: - Built-in defaults

    /// Bundle ID → persona ID. Non-exhaustive; apps not listed here get no
    /// automatic swap (the current persona is preserved).
    static let builtinDefaults: [String: String] = [
        "com.apple.dt.Xcode":          BuiltinPersonas.terseEngineerID,
        "com.microsoft.VSCode":        BuiltinPersonas.terseEngineerID,
        "com.apple.Terminal":          BuiltinPersonas.terseEngineerID,
        "com.googlecode.iterm2":       BuiltinPersonas.terseEngineerID,
        "com.apple.mail":              BuiltinPersonas.mumbaiBobID,
        "com.apple.Safari":            BuiltinPersonas.mumbaiBobID,
        "com.google.Chrome":           BuiltinPersonas.mumbaiBobID,
        "com.tinyspeck.slackmacgap":   BuiltinPersonas.grumpyLinusID,
    ]

    // MARK: - Merge

    /// Returns the effective mapping: built-in defaults overlaid with any
    /// user overrides. Overrides with an empty persona-id string are treated
    /// as explicit removals (the bundle id won't trigger any swap).
    static func effectiveMapping(overrides: [String: String]) -> [String: String] {
        var merged = builtinDefaults
        for (bundleID, personaID) in overrides {
            if personaID.isEmpty {
                merged.removeValue(forKey: bundleID)
            } else {
                merged[bundleID] = personaID
            }
        }
        return merged
    }

    // MARK: - Lookup

    /// Returns the persona ID for `bundleID` given the current override dict,
    /// or `nil` if no mapping exists (meaning: no swap should happen).
    static func personaID(
        for bundleID: String,
        overrides: [String: String] = [:]
    ) -> String? {
        effectiveMapping(overrides: overrides)[bundleID]
    }
}
