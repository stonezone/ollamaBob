import XCTest
@testable import OllamaBob

final class KeychainServiceTests: XCTestCase {

    // The real Keychain is global to the user account; using a dedicated
    // test service identifier so tests never collide with the production
    // identifier `com.ollamabob.secrets` and never leave stray secrets
    // around if a test fails before tearDown.
    private let testService = "com.ollamabob.tests.keychain"

    private func makeService() -> KeychainService {
        KeychainService(service: testService)
    }

    override func tearDown() {
        let svc = makeService()
        for key in KeychainSecretKey.allCases {
            try? svc.delete(key)
        }
        super.tearDown()
    }

    func testWriteAndReadRoundTrip() throws {
        let svc = makeService()
        try svc.write("brave-test-value", for: .braveAPIKey)
        XCTAssertEqual(svc.read(.braveAPIKey), "brave-test-value")
    }

    func testOverwriteExistingValue() throws {
        let svc = makeService()
        try svc.write("first", for: .jarvisAPIKey)
        try svc.write("second", for: .jarvisAPIKey)
        XCTAssertEqual(svc.read(.jarvisAPIKey), "second")
    }

    func testReadReturnsNilForMissingKey() {
        let svc = makeService()
        XCTAssertNil(svc.read(.elevenlabsAPIKey))
    }

    func testDeleteRemovesValue() throws {
        let svc = makeService()
        try svc.write("temp", for: .jarvisOperatorSecret)
        XCTAssertNotNil(svc.read(.jarvisOperatorSecret))
        try svc.delete(.jarvisOperatorSecret)
        XCTAssertNil(svc.read(.jarvisOperatorSecret))
    }

    func testDeleteIsIdempotent() {
        let svc = makeService()
        XCTAssertNoThrow(try svc.delete(.elevenlabsAPIKey))
        XCTAssertNoThrow(try svc.delete(.elevenlabsAPIKey))
    }

    func testReadTrimsWhitespaceAndReturnsNilOnEmpty() throws {
        let svc = makeService()
        // Whitespace-only payload should read back as nil — same contract
        // as LocalEnv and AppConfig accessor variants.
        try svc.write("   \n", for: .braveAPIKey)
        XCTAssertNil(svc.read(.braveAPIKey))
    }

    func testServiceIsolationBetweenInstances() throws {
        let svc1 = KeychainService(service: testService + ".one")
        let svc2 = KeychainService(service: testService + ".two")

        try svc1.write("alpha", for: .braveAPIKey)
        XCTAssertEqual(svc1.read(.braveAPIKey), "alpha")
        XCTAssertNil(svc2.read(.braveAPIKey))

        // Cleanup both
        try svc1.delete(.braveAPIKey)
        try svc2.delete(.braveAPIKey)
    }

    // MARK: - InMemorySecretStore parity

    func testInMemorySecretStoreSatisfiesProtocol() throws {
        let store = InMemorySecretStore()
        XCTAssertNil(store.read(.jarvisAPIKey))
        try store.write("hello", for: .jarvisAPIKey)
        XCTAssertEqual(store.read(.jarvisAPIKey), "hello")
        XCTAssertTrue(store.has(.jarvisAPIKey))
        try store.delete(.jarvisAPIKey)
        XCTAssertFalse(store.has(.jarvisAPIKey))
    }
}
