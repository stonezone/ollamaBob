import Foundation

enum PathPolicy {
    private static let allowed: [String] = [
        NSHomeDirectory(),
        "/tmp",
        "/var/tmp",
        "/Applications",
        "/usr/local"
    ]

    private static let sensitive: [String] = [
        "/System",
        "/Library",
        "/private",
        "/etc",
        "/var"  // except /var/tmp, handled in check()
    ]

    private static let forbidden: [String] = [
        "/dev",
        "/Volumes"
    ]

    static func check(_ path: String) -> PathAccess {
        guard let canonicalPath = canonicalize(path) else {
            return .requiresApproval
        }

        // Forbidden paths — always denied
        if forbiddenCanonical.contains(where: { matchesBoundary(canonicalPath, root: $0) }) {
            return .denied
        }

        // Allowed paths — no approval needed (/var/tmp is in the allowed list)
        if allowedCanonical.contains(where: { matchesBoundary(canonicalPath, root: $0) }) {
            return .allowed
        }

        // Sensitive paths — require approval
        if sensitiveCanonical.contains(where: { matchesBoundary(canonicalPath, root: $0) }) {
            return .requiresApproval
        }

        // Unknown paths — require approval
        return .requiresApproval
    }

    private static let allowedCanonical = canonicalRoots(allowed)
    private static let sensitiveCanonical = canonicalRoots(sensitive)
    private static let forbiddenCanonical = canonicalRoots(forbidden)

    private static func canonicalRoots(_ roots: [String]) -> [String] {
        roots.compactMap(canonicalize)
    }

    private static func canonicalize(_ path: String) -> String? {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath).standardizedFileURL.resolvingSymlinksInPath()
        return url.path.isEmpty ? nil : url.path
    }

    private static func matchesBoundary(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}
