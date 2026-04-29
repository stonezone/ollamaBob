import Foundation
import AppKit

/// One-time migration of legacy UserDefaults-resident secrets into the
/// macOS Keychain.
///
/// Phase 0c (peer-review plan, 2026-04-28). The migration:
///   1. Detects which legacy keys are present in UserDefaults.
///   2. Asks the user with a single modal NSAlert.
///   3. On approve, copies each value into the Keychain. Only after a
///      successful Keychain write does it remove the UserDefaults entry.
///   4. Appends a per-key result line to
///      `~/Library/Application Support/OllamaBob/migration.log` so the
///      operator can verify after the fact.
///   5. On deny, does nothing this launch and re-prompts next launch.
///
/// `.env` and `ProcessInfo.environment` are NOT migrated automatically;
/// users opt in per-key via the "Import from .env" button in Preferences.
@MainActor
enum SecretMigration {

    /// Legacy UserDefaults keys we know how to migrate.
    /// Keep this list in sync with `KeychainSecretKey` for the keys that
    /// historically had UserDefaults entries.
    static let legacyMappings: [(userDefaultsKey: String, secret: KeychainSecretKey)] = [
        ("braveAPIKey", .braveAPIKey),
        ("jarvisAPIKey", .jarvisAPIKey),
        ("jarvisOperatorSecret", .jarvisOperatorSecret)
    ]

    enum Outcome: Equatable {
        case nothingToMigrate
        case userDeclined
        case migrated([Result])
    }

    struct Result: Equatable {
        let userDefaultsKey: String
        let secret: KeychainSecretKey
        let success: Bool
        let detail: String
    }

    /// Returns the legacy keys whose values are non-empty in UserDefaults
    /// and absent (or empty) in the secret store.
    static func pendingMigrations(
        defaults: UserDefaults = .standard,
        secrets: SecretStoring = KeychainService.current
    ) -> [(userDefaultsKey: String, secret: KeychainSecretKey, value: String)] {
        legacyMappings.compactMap { mapping in
            let value = (defaults.string(forKey: mapping.userDefaultsKey) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            // If the Keychain already has a non-empty value, the migration
            // has already happened (or the user set it directly there).
            // Treat as nothing to do for that key.
            if let existing = secrets.read(mapping.secret), !existing.isEmpty {
                return nil
            }
            return (mapping.userDefaultsKey, mapping.secret, value)
        }
    }

    /// Runs the migration if needed. Presents the prompt synchronously on
    /// the main actor; intended to be called once from the app launch path.
    /// Test callers should use `performMigration(_:defaults:secrets:logURL:)`.
    @discardableResult
    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        secrets: SecretStoring = KeychainService.current,
        confirm: @MainActor () -> Bool = SecretMigration.defaultConfirm
    ) -> Outcome {
        let pending = pendingMigrations(defaults: defaults, secrets: secrets)
        guard !pending.isEmpty else { return .nothingToMigrate }

        guard confirm() else { return .userDeclined }

        let results = performMigration(
            pending,
            defaults: defaults,
            secrets: secrets,
            logURL: defaultLogURL()
        )
        return .migrated(results)
    }

    /// Pure migration step. Public so tests can drive it without an NSAlert.
    static func performMigration(
        _ pending: [(userDefaultsKey: String, secret: KeychainSecretKey, value: String)],
        defaults: UserDefaults,
        secrets: SecretStoring,
        logURL: URL?
    ) -> [Result] {
        var results: [Result] = []
        for entry in pending {
            do {
                try secrets.write(entry.value, for: entry.secret)
                // Only remove the UserDefaults entry AFTER the Keychain
                // write confirms, so a write failure cannot lose the secret.
                defaults.removeObject(forKey: entry.userDefaultsKey)
                results.append(Result(
                    userDefaultsKey: entry.userDefaultsKey,
                    secret: entry.secret,
                    success: true,
                    detail: "migrated"
                ))
            } catch {
                results.append(Result(
                    userDefaultsKey: entry.userDefaultsKey,
                    secret: entry.secret,
                    success: false,
                    detail: "keychain write failed: \(error)"
                ))
            }
        }
        if let logURL { append(results: results, to: logURL) }
        return results
    }

    /// Default modal prompt. Returns true on Approve, false on Decide later.
    @MainActor
    static func defaultConfirm() -> Bool {
        let pending = pendingMigrations()
        let count = pending.count
        let keyList = pending
            .map { "\($0.userDefaultsKey) -> \($0.secret.rawValue)" }
            .joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = "Move \(count) API key\(count == 1 ? "" : "s") to the macOS Keychain?"
        alert.informativeText = """
        OllamaBob will move your stored API keys (Brave, Jarvis) from the
        app's preferences plist into the macOS Keychain so they're never
        on disk in plaintext. You can decide later — Bob will keep using
        the existing values until you approve.
        """
        if !keyList.isEmpty {
            let details = NSTextField(wrappingLabelWithString: "Details:\n\(keyList)")
            details.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            details.textColor = .secondaryLabelColor
            details.frame = NSRect(x: 0, y: 0, width: 360, height: 54)
            alert.accessoryView = details
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Approve")
        alert.addButton(withTitle: "Decide later")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Imports a single key from `.env` / process env into the Keychain
    /// when the user clicks "Import from .env" next to the field in
    /// Preferences.
    @discardableResult
    static func importFromEnvironment(
        _ secret: KeychainSecretKey,
        secrets: SecretStoring = KeychainService.current,
        env: (String) -> String? = { ProcessInfo.processInfo.environment[$0] },
        localEnv: (String) -> String? = LocalEnv.value(for:)
    ) -> Result? {
        let envValue = (env(secret.rawValue) ?? localEnv(secret.rawValue) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !envValue.isEmpty else { return nil }
        do {
            try secrets.write(envValue, for: secret)
            let result = Result(
                userDefaultsKey: secret.rawValue,
                secret: secret,
                success: true,
                detail: "imported from environment"
            )
            if let logURL = defaultLogURL() {
                append(results: [result], to: logURL)
            }
            return result
        } catch {
            return Result(
                userDefaultsKey: secret.rawValue,
                secret: secret,
                success: false,
                detail: "keychain write failed: \(error)"
            )
        }
    }

    /// `~/Library/Application Support/OllamaBob/migration.log`. Returns nil
    /// only if the support directory cannot be created.
    static func defaultLogURL() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("OllamaBob", isDirectory: true)
        if fm.fileExists(atPath: dir.path) == false {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }
        return dir.appendingPathComponent("migration.log")
    }

    private static func append(results: [Result], to url: URL) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
        var lines: [String] = []
        for r in results {
            // Never log the actual secret value. Log the key NAME and the
            // outcome so the operator can verify migration worked.
            lines.append("\(timestamp) secret=\(r.secret.rawValue) success=\(r.success) detail=\(r.detail)")
        }
        let payload = (lines.joined(separator: "\n") + "\n").data(using: .utf8) ?? Data()
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: payload)
            }
        } else {
            try? payload.write(to: url, options: .atomic)
        }
    }
}
