import XCTest
@testable import OllamaBob

@MainActor
final class SecretMigrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "secret-migration-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Detection

    func testPendingMigrationsReturnsKeysWithUserDefaultsValue() {
        let store = InMemorySecretStore()
        defaults.set("brave-stored", forKey: "braveAPIKey")
        defaults.set("jarvis-stored", forKey: "jarvisAPIKey")

        let pending = SecretMigration.pendingMigrations(defaults: defaults, secrets: store)

        let secrets = pending.map(\.secret).sorted { $0.rawValue < $1.rawValue }
        XCTAssertEqual(secrets, [.braveAPIKey, .jarvisAPIKey])
    }

    func testPendingMigrationsSkipsKeyAlreadyInKeychain() throws {
        let store = InMemorySecretStore()
        try store.write("existing", for: .braveAPIKey)
        defaults.set("brave-from-defaults", forKey: "braveAPIKey")

        let pending = SecretMigration.pendingMigrations(defaults: defaults, secrets: store)

        XCTAssertTrue(pending.isEmpty)
    }

    func testPendingMigrationsSkipsEmptyOrWhitespaceUserDefaultsValues() {
        let store = InMemorySecretStore()
        defaults.set("   ", forKey: "braveAPIKey")
        defaults.set("", forKey: "jarvisAPIKey")

        let pending = SecretMigration.pendingMigrations(defaults: defaults, secrets: store)

        XCTAssertTrue(pending.isEmpty)
    }

    // MARK: - Migration

    func testPerformMigrationWritesKeychainAndClearsUserDefaults() {
        let store = InMemorySecretStore()
        defaults.set("brave", forKey: "braveAPIKey")
        defaults.set("jarvis", forKey: "jarvisAPIKey")
        defaults.set("op-secret", forKey: "jarvisOperatorSecret")

        let pending = SecretMigration.pendingMigrations(defaults: defaults, secrets: store)
        XCTAssertEqual(pending.count, 3)

        let results = SecretMigration.performMigration(pending, defaults: defaults, secrets: store, logURL: nil)

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.allSatisfy(\.success))

        XCTAssertEqual(store.read(.braveAPIKey), "brave")
        XCTAssertEqual(store.read(.jarvisAPIKey), "jarvis")
        XCTAssertEqual(store.read(.jarvisOperatorSecret), "op-secret")

        XCTAssertNil(defaults.string(forKey: "braveAPIKey"))
        XCTAssertNil(defaults.string(forKey: "jarvisAPIKey"))
        XCTAssertNil(defaults.string(forKey: "jarvisOperatorSecret"))
    }

    func testPerformMigrationKeepsUserDefaultsWhenKeychainWriteFails() {
        let store = AlwaysFailSecretStore()
        defaults.set("brave-keep", forKey: "braveAPIKey")

        let pending = [(userDefaultsKey: "braveAPIKey", secret: KeychainSecretKey.braveAPIKey, value: "brave-keep")]
        let results = SecretMigration.performMigration(pending, defaults: defaults, secrets: store, logURL: nil)

        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].success)
        // The legacy entry MUST stay so we don't lose the secret on a Keychain failure.
        XCTAssertEqual(defaults.string(forKey: "braveAPIKey"), "brave-keep")
    }

    // MARK: - runIfNeeded prompt orchestration

    func testRunIfNeededReturnsNothingWhenNoLegacyKeysPresent() {
        let store = InMemorySecretStore()
        let outcome = SecretMigration.runIfNeeded(defaults: defaults, secrets: store, confirm: { false })
        XCTAssertEqual(outcome, .nothingToMigrate)
    }

    func testRunIfNeededRespectsUserDecline() {
        let store = InMemorySecretStore()
        defaults.set("brave", forKey: "braveAPIKey")

        let outcome = SecretMigration.runIfNeeded(defaults: defaults, secrets: store, confirm: { false })
        XCTAssertEqual(outcome, .userDeclined)
        // Decline keeps the legacy secret intact.
        XCTAssertEqual(defaults.string(forKey: "braveAPIKey"), "brave")
        XCTAssertNil(store.read(.braveAPIKey))
    }

    func testRunIfNeededMigratesOnApprove() {
        let store = InMemorySecretStore()
        defaults.set("brave", forKey: "braveAPIKey")
        defaults.set("jarvis", forKey: "jarvisAPIKey")

        let outcome = SecretMigration.runIfNeeded(defaults: defaults, secrets: store, confirm: { true })

        guard case .migrated(let results) = outcome else {
            return XCTFail("Expected migrated outcome, got \(outcome)")
        }
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy(\.success))
        XCTAssertEqual(store.read(.braveAPIKey), "brave")
        XCTAssertEqual(store.read(.jarvisAPIKey), "jarvis")
        XCTAssertNil(defaults.string(forKey: "braveAPIKey"))
        XCTAssertNil(defaults.string(forKey: "jarvisAPIKey"))
    }

    // MARK: - Import-from-environment path

    func testImportFromEnvironmentWritesValueWhenPresent() {
        let store = InMemorySecretStore()
        let result = SecretMigration.importFromEnvironment(
            .braveAPIKey,
            secrets: store,
            env: { _ in "from-env" },
            localEnv: { _ in nil }
        )
        XCTAssertEqual(result?.success, true)
        XCTAssertEqual(store.read(.braveAPIKey), "from-env")
    }

    func testImportFromEnvironmentFallsBackToLocalEnv() {
        let store = InMemorySecretStore()
        let result = SecretMigration.importFromEnvironment(
            .jarvisAPIKey,
            secrets: store,
            env: { _ in nil },
            localEnv: { _ in "from-dotenv" }
        )
        XCTAssertEqual(result?.success, true)
        XCTAssertEqual(store.read(.jarvisAPIKey), "from-dotenv")
    }

    func testImportFromEnvironmentReturnsNilWhenNoSource() {
        let store = InMemorySecretStore()
        let result = SecretMigration.importFromEnvironment(
            .elevenlabsAPIKey,
            secrets: store,
            env: { _ in nil },
            localEnv: { _ in nil }
        )
        XCTAssertNil(result)
    }
}

// MARK: - Test helpers

private final class AlwaysFailSecretStore: SecretStoring, @unchecked Sendable {
    func read(_ key: KeychainSecretKey) -> String? { nil }
    func write(_ value: String, for key: KeychainSecretKey) throws {
        throw KeychainError.unhandled(-1)
    }
    func delete(_ key: KeychainSecretKey) throws {}
}
