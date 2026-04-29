import XCTest
@testable import OllamaBob

final class FocusBundleMappingTests: XCTestCase {

    // MARK: - Built-in defaults

    func testDefaultMappingReturnsTermseEngineerForXcode() {
        let personaID = FocusBundleMapping.personaID(for: "com.apple.dt.Xcode")
        XCTAssertEqual(personaID, BuiltinPersonas.terseEngineerID,
                       "Xcode should map to terseEngineer by default")
    }

    func testDefaultMappingReturnsTermseEngineerForVSCode() {
        let personaID = FocusBundleMapping.personaID(for: "com.microsoft.VSCode")
        XCTAssertEqual(personaID, BuiltinPersonas.terseEngineerID)
    }

    func testDefaultMappingReturnsMumbaiBobForMail() {
        let personaID = FocusBundleMapping.personaID(for: "com.apple.mail")
        XCTAssertEqual(personaID, BuiltinPersonas.mumbaiBobID,
                       "Mail should map to mumbaiBob by default")
    }

    func testDefaultMappingReturnsMumbaiBobForSafari() {
        let personaID = FocusBundleMapping.personaID(for: "com.apple.Safari")
        XCTAssertEqual(personaID, BuiltinPersonas.mumbaiBobID)
    }

    func testDefaultMappingReturnsGrumpyLinusForSlack() {
        let personaID = FocusBundleMapping.personaID(for: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(personaID, BuiltinPersonas.grumpyLinusID)
    }

    // MARK: - Unknown bundle IDs

    func testUnknownBundleIDReturnsNil() {
        let personaID = FocusBundleMapping.personaID(for: "com.example.unknown.app")
        XCTAssertNil(personaID,
                     "An unmapped bundle ID should return nil (no swap)")
    }

    func testEmptyBundleIDReturnsNil() {
        let personaID = FocusBundleMapping.personaID(for: "")
        XCTAssertNil(personaID)
    }

    // MARK: - User overrides beat built-in defaults

    func testUserOverrideBeatBuiltinForSameKey() {
        // Override Xcode → helpfulAssistant instead of terseEngineer
        let overrides = ["com.apple.dt.Xcode": BuiltinPersonas.helpfulAssistID]
        let personaID = FocusBundleMapping.personaID(for: "com.apple.dt.Xcode",
                                                     overrides: overrides)
        XCTAssertEqual(personaID, BuiltinPersonas.helpfulAssistID,
                       "User override should win over built-in default")
    }

    func testUserOverrideCanAddNewBundleID() {
        // Add a brand-new mapping not in the built-in list
        let overrides = ["com.apple.Finder": BuiltinPersonas.grumpyLinusID]
        let personaID = FocusBundleMapping.personaID(for: "com.apple.Finder",
                                                     overrides: overrides)
        XCTAssertEqual(personaID, BuiltinPersonas.grumpyLinusID)
    }

    func testUserOverrideWithEmptyValueRemovesBuiltinEntry() {
        // Empty value string is treated as "remove this mapping"
        let overrides = ["com.apple.dt.Xcode": ""]
        let personaID = FocusBundleMapping.personaID(for: "com.apple.dt.Xcode",
                                                     overrides: overrides)
        XCTAssertNil(personaID,
                     "An empty override value should suppress the built-in mapping")
    }

    func testEmptyOverridesDictDoesNotMutateBuiltins() {
        let merged = FocusBundleMapping.effectiveMapping(overrides: [:])
        XCTAssertEqual(merged, FocusBundleMapping.builtinDefaults,
                       "Empty overrides should leave built-ins unchanged")
    }
}
