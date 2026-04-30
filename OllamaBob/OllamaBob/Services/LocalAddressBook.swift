import Foundation

/// Best-effort local address-book loader for Jarvis call shortcuts.
///
/// This is intentionally lightweight: it looks for local JSON alias maps
/// and VCF exports, then resolves simple alias -> phone number mappings.
/// Repo-local env numbers also seed a few useful aliases so `call me`
/// works even before the user creates a dedicated file.
enum LocalAddressBook {
    private static let values: [String: String] = loadValues()

    static func value(for key: String) -> String? {
        let trimmed = values[canonicalKey(key)]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Snapshot of all known alias→number pairs, sorted by alias for stable
    /// rendering. Empty when no env-seeded numbers and no file-based imports
    /// are present. Pairs are deduplicated by canonical alias.
    static func allEntries() -> [(alias: String, number: String)] {
        values
            .map { (alias: $0.key, number: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.number.isEmpty }
            .sorted { $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending }
    }

    private static func loadValues() -> [String: String] {
        var merged = seededAliases()

        for url in candidateAddressBookURLs() {
            guard let data = try? Data(contentsOf: url) else { continue }
            let parsed = parse(data)
            for (key, value) in parsed {
                merged[key] = value
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

        func addIfExists(_ candidate: URL, fileManager: FileManager) {
            let path = candidate.path
            if seen.insert(path).inserted, fileManager.fileExists(atPath: path) {
                urls.append(candidate)
            }
        }

        func addAncestors(startingAt url: URL) {
            var current = url.resolvingSymlinksInPath().standardizedFileURL
            let fileManager = FileManager.default

            for _ in 0..<64 {
                for fileName in [
                    "bobs_contacts.vcf",
                    "jarvis-address-book.local.vcf",
                    "jarvis-address-book.vcf",
                    "jarvis-address-book.local.json",
                    "jarvis-address-book.json"
                ] {
                    let candidate = current.appendingPathComponent(fileName)
                    addIfExists(candidate, fileManager: fileManager)
                }

                let parent = current.deletingLastPathComponent().standardizedFileURL
                if parent.path == current.path || current.path == "/" || current.path.isEmpty {
                    break
                }
                current = parent
            }
        }

        let downloadsVCF = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Downloads")
            .appendingPathComponent("bobs_contacts.vcf")
        addIfExists(downloadsVCF, fileManager: .default)
        addAncestors(startingAt: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        addAncestors(startingAt: Bundle.main.bundleURL)
        return urls
    }

    static func parse(_ data: Data) -> [String: String] {
        if let json = parseJSON(data), json.isEmpty == false {
            return json
        }
        return parseVCF(data)
    }

    private static func parseJSON(_ data: Data) -> [String: String]? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any] else {
            return nil
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

    private static func parseVCF(_ data: Data) -> [String: String] {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            return [:]
        }

        let contacts = vCards(in: text).compactMap { card -> VCardContact? in
            let phone = preferredPhone(in: card)
            guard phone.isEmpty == false else { return nil }
            return VCardContact(phone: phone, aliases: aliases(in: card), givenName: givenName(in: card))
        }

        let givenNameCounts = Dictionary(
            grouping: contacts.compactMap { contact -> String? in
                guard let givenName = contact.givenName else { return nil }
                let canonical = canonicalKey(givenName)
                return canonical.isEmpty ? nil : canonical
            },
            by: { $0 }
        ).mapValues(\.count)

        var parsed: [String: String] = [:]
        for contact in contacts {
            var contactAliases = contact.aliases
            if let givenName = contact.givenName,
               givenNameCounts[canonicalKey(givenName)] == 1 {
                contactAliases.append(givenName)
            }

            for alias in contactAliases {
                let canonical = canonicalKey(alias)
                if canonical.isEmpty == false {
                    parsed[canonical] = contact.phone
                }
            }
        }
        return parsed
    }

    private static func vCards(in text: String) -> [[VCardLine]] {
        var cards: [[VCardLine]] = []
        var current: [VCardLine] = []
        var inCard = false

        for rawLine in unfoldedVCardLines(text) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false else { continue }

            if line.localizedCaseInsensitiveCompare("BEGIN:VCARD") == .orderedSame {
                current = []
                inCard = true
                continue
            }
            if line.localizedCaseInsensitiveCompare("END:VCARD") == .orderedSame {
                if inCard, current.isEmpty == false {
                    cards.append(current)
                }
                current = []
                inCard = false
                continue
            }
            guard inCard, let parsedLine = VCardLine(line) else { continue }
            current.append(parsedLine)
        }

        return cards
    }

    private static func unfoldedVCardLines(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []

        for rawLine in normalized.components(separatedBy: "\n") {
            if rawLine.hasPrefix(" ") || rawLine.hasPrefix("\t") {
                if lines.isEmpty {
                    lines.append(String(rawLine.dropFirst()))
                } else {
                    lines[lines.count - 1] += String(rawLine.dropFirst())
                }
            } else {
                lines.append(rawLine)
            }
        }

        return lines
    }

    private static func aliases(in card: [VCardLine]) -> [String] {
        var aliases: [String] = []

        for key in ["FN", "NICKNAME", "ORG"] {
            aliases.append(contentsOf: card.filter { $0.name == key }.map(\.decodedValue))
        }

        for nameLine in card.filter({ $0.name == "N" }) {
            let parts = nameLine.decodedValue
                .split(separator: ";", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            let given = parts.count > 1 ? parts[1] : ""
            let family = parts.first ?? ""
            let full = [given, family]
                .filter { $0.isEmpty == false }
                .joined(separator: " ")
            aliases.append(full)
        }

        return Array(Set(aliases.map { unescapedVCardValue($0) }))
    }

    private static func givenName(in card: [VCardLine]) -> String? {
        guard let nameLine = card.first(where: { $0.name == "N" }) else { return nil }
        let parts = nameLine.decodedValue
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { unescapedVCardValue(String($0)) }
        guard parts.count > 1 else { return nil }
        return parts[1].isEmpty ? nil : parts[1]
    }

    private static func preferredPhone(in card: [VCardLine]) -> String {
        let phones = card
            .filter { $0.name == "TEL" }
            .map { line in
                (value: normalizedPhoneValue(line.decodedValue), rank: phoneRank(line.rawName.lowercased()))
            }
            .filter { $0.value.isEmpty == false }
            .sorted { $0.rank < $1.rank }

        return phones.first?.value ?? ""
    }

    private static func phoneRank(_ rawName: String) -> Int {
        if rawName.contains("pref") { return 0 }
        if rawName.contains("cell") || rawName.contains("mobile") || rawName.contains("iphone") { return 1 }
        if rawName.contains("voice") { return 2 }
        if rawName.contains("fax") { return 9 }
        return 3
    }

    private static func normalizedPhoneValue(_ value: String) -> String {
        let trimmed = unescapedVCardValue(value)
            .replacingOccurrences(of: "tel:", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        return trimmed
    }

    private static func unescapedVCardValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: " ", options: [.caseInsensitive])
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonicalKey(_ key: String) -> String {
        key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private struct VCardLine {
        let rawName: String
        let name: String
        let decodedValue: String

        init?(_ line: String) {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let rawName = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let baseName = rawName
                .split(separator: ";", maxSplits: 1)
                .first?
                .split(separator: ".")
                .last
                .map(String.init) ?? rawName
            self.rawName = rawName
            self.name = baseName.uppercased()
            self.decodedValue = value
        }
    }

    private struct VCardContact {
        let phone: String
        var aliases: [String]
        let givenName: String?
    }
}
