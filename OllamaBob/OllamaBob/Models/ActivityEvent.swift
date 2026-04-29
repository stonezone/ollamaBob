import Foundation

struct ActivityEvent: Equatable, Sendable {
    var id: Int64?
    var timestamp: Date
    var source: String
    var kind: String
    var detail: String
    var conversationID: String?
    var metadataJSON: String?
}
