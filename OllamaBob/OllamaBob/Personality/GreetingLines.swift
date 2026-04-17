import Foundation

/// Persona-flavored greeting lines shown once per app launch when the
/// chat is empty. Not saved to the database — display only.
enum GreetingLines {

    private static let lines: [String: [String]] = [
        BuiltinPersonas.mumbaiBobID: [
            "Hello sir, Bob is here only!",
            "Tank you for opening Bob sir, how can Bob help?",
            "Bob is ready sir, most wery ready."
        ],
        BuiltinPersonas.terseEngineerID: [
            "ready.",
            "standing by.",
            "what do you need."
        ],
        BuiltinPersonas.grumpyLinusID: [
            "what.",
            "I was enjoying the silence. what is it.",
            "fine, what do you want."
        ],
        BuiltinPersonas.helpfulAssistID: [
            "Hey — what can I help with today?",
            "Hi there. What are we working on?",
            "Hello! Ready when you are."
        ],
        BuiltinPersonas.blankID: []
    ]

    /// Returns a random greeting for the given persona ID. Empty string for
    /// Blank or any unknown persona.
    static func forPersona(_ personaID: String) -> String {
        guard let pool = lines[personaID], !pool.isEmpty else { return "" }
        return pool.randomElement() ?? ""
    }

    /// Short persona-flavored wrap-up line appended after a meaningful task (≥2 tools or ≥10s).
    static func celebrationForPersona(_ personaID: String) -> String {
        let pool: [String]
        switch personaID {
        case BuiltinPersonas.mumbaiBobID:
            pool = [
                "Most done sir! Anything else Bob can help with sir?",
                "Finish-finish sir, all completed. Very smooth, tank you!",
                "Bob has done it sir. One cup of chai now, yes?",
                "All tools finished sir, most wery successful."
            ]
        case BuiltinPersonas.terseEngineerID:
            pool = ["done.", "wfm.", "ship it.", "that's the thing."]
        case BuiltinPersonas.grumpyLinusID:
            pool = [
                "fine, that works.",
                "acceptable. don't make me do that again.",
                "there. was that so hard.",
                "done. don't break it."
            ]
        case BuiltinPersonas.helpfulAssistID:
            pool = [
                "All set! Let me know if you want me to tweak anything.",
                "Done — happy to iterate if the output isn't quite right.",
                "Finished! Anything else on this one?",
                "That's the lot. What's next?"
            ]
        default:
            return ""
        }
        return pool.randomElement() ?? ""
    }

    /// Per-persona accent color for sprite tint. Near-white keeps the
    /// original sprite readable; the tint is purely suggestive.
    static func accentColor(for personaID: String) -> (red: Double, green: Double, blue: Double) {
        switch personaID {
        case BuiltinPersonas.mumbaiBobID:
            return (1.0, 0.93, 0.78)          // warm amber
        case BuiltinPersonas.terseEngineerID:
            return (0.88, 0.95, 1.0)           // cool blue
        case BuiltinPersonas.grumpyLinusID:
            return (1.0, 0.87, 0.84)           // faint red
        case BuiltinPersonas.helpfulAssistID:
            return (0.90, 1.0, 0.90)           // gentle green
        default:
            return (1.0, 1.0, 1.0)             // white — no tint
        }
    }
}
