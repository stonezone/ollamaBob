import Foundation

/// Best-effort local address-book loader for Jarvis call shortcuts.
///
/// This is intentionally lightweight: it looks for a repo-local
/// `jarvis-address-book.local.json` first, then a checked-in
/// `jarvis-address-book.example.json` template. Values are simple alias ->
/// phone number mappings. Repo-local env numbers also seed a few useful
/// aliases so `call me` works even before the user creates a dedicated file.
enum LocalAddressBook {
    private static let values: [String: String] = loadValues()

    static func value(for key: String) -> String? {
        let trimmed = values[canonicalKey(key)]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func loadValues() -> [String: String] {
        var merged = seededAliases()

        for url in candidateAddressBookURLs() {
            guard let data = try? Data(contentsOf: url) else { continue }
            let parsed = parse(data)
            for (key, value) in parsed {
                merged[key] = value
            }
            if parsed.isEmpty == false {
                break
            }
        }

        return merged
    }

    private static func seededAliases() -> [String: String] {
        var seeded: [String: String] = [:]

        if let zack = LocalEnv.value(for: "ZACK_PERSONAL_NUMBER") {
            for alias in ["me", "myself", "zack", "zack personal", "my phone"] {
                seeded[alias] = zack
            }
        }

        if let glennel = LocalEnv.value(for: "GLENNEL_PERSONAL_NUMBER") {
            for alias in ["glennel", "wife", "partner", "glennel personal"] {
                seeded[alias] = glennel
            }
        }

        return seeded
    }

    private static func candidateAddressBookURLs() -> [URL] {
        var urls: [URL] = []
        var seen: Set<String> = []

        func addAncestors(startingAt url: URL) {
            var current = url.resolvingSymlinksInPath().standardizedFileURL
            let fileManager = FileManager.default

            for _ in 0..<64 {
                for fileName in ["jarvis-address-book.local.json", "jarvis-address-book.json"] {
                    let candidate = current.appendingPathComponent(fileName)
                    let path = candidate.path
                    if seen.insert(path).inserted, fileManager.fileExists(atPath: path) {
                        urls.append(candidate)
                    }
                }

                let parent = current.deletingLastPathComponent().standardizedFileURL
                if parent.path == current.path || current.path == "/" || current.path.isEmpty {
                    break
                }
                current = parent
            }
        }

        addAncestors(startingAt: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        addAncestors(startingAt: Bundle.main.bundleURL)
        return urls
    }

    private static func parse(_ data: Data) -> [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else {
            return [:]
        }

        var parsed: [String: String] = [:]
        for (key, value) in dictionary {
            guard let stringValue = value as? String else { continue }
            let canonical = canonicalKey(key)
            if canonical.isEmpty == false {
                parsed[canonical] = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return parsed
    }

    private static func canonicalKey(_ key: String) -> String {
        key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
