import Foundation

struct SearchResult: Sendable {
    let title: String
    let url: String
    let snippet: String
}

protocol SearchProvider: Sendable {
    func search(query: String) async throws -> [SearchResult]
}
