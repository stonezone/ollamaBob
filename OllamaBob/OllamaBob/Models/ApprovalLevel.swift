import Foundation

enum ApprovalLevel: String, Codable, Sendable {
    case none       // Execute silently, log only
    case modal      // NSAlert blocks until user explicitly approves
    case forbidden  // Never execute, tell model "not allowed"
}

enum ToolApprovalSetting: String, Codable, CaseIterable, Sendable {
    case auto
    case ask
    case deny

    var badgeLabel: String {
        switch self {
        case .auto: return "AUTO"
        case .ask:  return "ASK"
        case .deny: return "DENY"
        }
    }

    var next: ToolApprovalSetting {
        switch self {
        case .auto: return .ask
        case .ask:  return .deny
        case .deny: return .auto
        }
    }
}

enum PathAccess: Sendable {
    case allowed
    case requiresApproval
    case denied
}
