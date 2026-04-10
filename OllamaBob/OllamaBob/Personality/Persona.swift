import Foundation

/// A user-facing persona that controls Bob's voice and tone.
/// Persona prompts do NOT contain safety rails or tool-calling rules —
/// those live in `BobOperatingRules` and are prepended at turn time.
///
/// `systemPromptMarkdown` is stored as markdown-friendly text so users can
/// read and edit it in the Preferences → Personas tab without learning JSON.
struct Persona: Identifiable, Hashable {
    let id: String
    let name: String
    let systemPromptMarkdown: String
    let isBuiltin: Bool
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String,
        name: String,
        systemPromptMarkdown: String,
        isBuiltin: Bool,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.systemPromptMarkdown = systemPromptMarkdown
        self.isBuiltin = isBuiltin
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
