import Foundation
import Security

/// Minimal Keychain wrapper for OllamaBob secrets.
///
/// Phase 0c (peer-review plan, 2026-04-28): added so API keys live in the
/// macOS Keychain instead of UserDefaults. Backed by `kSecClassGenericPassword`
/// with `kSecAttrAccessibleAfterFirstUnlock` so secrets survive reboots but
/// stay locked until the user is signed in once.
///
/// `SecretStoring` is the protocol so tests can inject `InMemorySecretStore`
/// without touching the real Keychain. Production code uses
/// `KeychainService.shared`.
enum KeychainSecretKey: String, CaseIterable, Sendable {
    case braveAPIKey = "BRAVE_API_KEY"
    case jarvisAPIKey = "JARVIS_API_KEY"
    case jarvisOperatorSecret = "OPERATOR_API_SECRET"
    case elevenlabsAPIKey = "ELEVENLABS_API_KEY"
}

enum KeychainError: Error, Equatable {
    case unhandled(OSStatus)
    case dataConversionFailed
}

protocol SecretStoring: Sendable {
    func read(_ key: KeychainSecretKey) -> String?
    func write(_ value: String, for key: KeychainSecretKey) throws
    func delete(_ key: KeychainSecretKey) throws
}

extension SecretStoring {
    func has(_ key: KeychainSecretKey) -> Bool { read(key) != nil }
}

final class KeychainService: SecretStoring {
    static let shared = KeychainService()

    /// Override hook for tests. When non-nil, `KeychainService.current`
    /// returns this value instead of the real-Keychain `shared`. Production
    /// code MUST call `KeychainService.current` (not `.shared`) so tests
    /// can swap in `InMemorySecretStore` and never read real secrets.
    /// `nonisolated(unsafe)` is appropriate here: tests own the lifecycle
    /// (set in setUp, clear in tearDown) and this is the test seam.
    nonisolated(unsafe) static var testOverride: SecretStoring?

    /// Production callers use this. It returns the test override when one
    /// is installed, otherwise the real-Keychain singleton. Anywhere we
    /// said `KeychainService.shared.read(...)` we now say
    /// `KeychainService.current.read(...)`.
    static var current: SecretStoring {
        testOverride ?? shared
    }

    /// Service name segregates OllamaBob's secrets from anything else
    /// the user has in the login keychain. Bundle id would also work;
    /// using a stable string keeps tests independent of bundle identity.
    private let service: String

    init(service: String = "com.ollamabob.secrets") {
        self.service = service
    }

    func read(_ key: KeychainSecretKey) -> String? {
        var query: [CFString: Any] = baseQuery(for: key)
        query[kSecReturnData] = kCFBooleanTrue!
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func write(_ value: String, for key: KeychainSecretKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        let query = baseQuery(for: key)
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            for (k, v) in attributes { addQuery[k] = v }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(addStatus)
            }
            return
        }

        throw KeychainError.unhandled(updateStatus)
    }

    func delete(_ key: KeychainSecretKey) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound is fine — we wanted it gone, it's gone.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func baseQuery(for key: KeychainSecretKey) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue
        ]
    }
}

/// In-memory secret store for tests. Same protocol as the real Keychain
/// service so the migration logic can be unit-tested without touching
/// the user's login keychain.
final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private var values: [KeychainSecretKey: String] = [:]
    private let lock = NSLock()

    func read(_ key: KeychainSecretKey) -> String? {
        lock.lock(); defer { lock.unlock() }
        let trimmed = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func write(_ value: String, for key: KeychainSecretKey) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    func delete(_ key: KeychainSecretKey) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}
