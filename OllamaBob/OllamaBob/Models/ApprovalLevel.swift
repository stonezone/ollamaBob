import Foundation

enum ApprovalLevel: String, Codable, Sendable {
    case none       // Execute silently, log only
    case modal      // NSAlert blocks until user explicitly approves
    case forbidden  // Never execute, tell model "not allowed"
}

enum PathAccess: Sendable {
    case allowed
    case requiresApproval
    case denied
}
