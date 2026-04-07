import Foundation

enum PathPolicy {
    static let allowed: [String] = [
        NSHomeDirectory(),
        "/tmp",
        "/var/tmp",
        "/Applications",
        "/usr/local"
    ]

    static let sensitive: [String] = [
        "/System",
        "/Library",
        "/private",
        "/etc",
        "/var"  // except /var/tmp, handled in check()
    ]

    static let forbidden: [String] = [
        "/dev",
        "/Volumes"
    ]

    static func check(_ path: String) -> PathAccess {
        let expandedPath = NSString(string: path).expandingTildeInPath

        // Forbidden paths — always denied
        if forbidden.contains(where: { expandedPath.hasPrefix($0) }) {
            return .denied
        }

        // Allowed paths — no approval needed (/var/tmp is in the allowed list)
        if allowed.contains(where: { expandedPath.hasPrefix($0) }) {
            return .allowed
        }

        // Sensitive paths — require approval
        if sensitive.contains(where: { expandedPath.hasPrefix($0) }) {
            return .requiresApproval
        }

        // Unknown paths — require approval
        return .requiresApproval
    }
}
