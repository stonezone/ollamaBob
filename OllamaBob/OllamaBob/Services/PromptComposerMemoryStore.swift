import Foundation

protocol PromptComposerMemoryStoring {
    func fetchActiveFacts() throws -> [FactRecord]
    func touchFacts(ids: [String]) throws
}

struct DatabasePromptComposerMemoryStore: PromptComposerMemoryStoring {
    func fetchActiveFacts() throws -> [FactRecord] {
        try DatabaseManager.shared.fetchActiveFacts()
    }

    func touchFacts(ids: [String]) throws {
        try DatabaseManager.shared.touchFacts(ids: ids)
    }
}
