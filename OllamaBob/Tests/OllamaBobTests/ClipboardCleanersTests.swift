import XCTest
@testable import OllamaBob

/// Tests for `ClipboardCleaners`.
///
/// All tests exercise pure transforms — no NSPasteboard access, no model
/// invocation.
final class ClipboardCleanersTests: XCTestCase {

    // MARK: - cleanURL

    func testCleanURL_stripsUtmParams() {
        let dirty = "https://example.com/blog?utm_source=newsletter&utm_medium=email&utm_campaign=spring"
        let cleaned = ClipboardCleaners.cleanURL(dirty)
        XCTAssertNotNil(cleaned)
        XCTAssertFalse(cleaned!.contains("utm_source"))
        XCTAssertFalse(cleaned!.contains("utm_medium"))
        XCTAssertFalse(cleaned!.contains("utm_campaign"))
    }

    func testCleanURL_stripsFbclid() {
        let dirty = "https://example.com/?fbclid=IwAR0abc123&id=42"
        let cleaned = ClipboardCleaners.cleanURL(dirty)
        XCTAssertNotNil(cleaned)
        XCTAssertFalse(cleaned!.contains("fbclid"))
    }

    func testCleanURL_stripsGclid() {
        let dirty = "https://example.com/?gclid=Cj0KCQjwxyz&q=widget"
        let cleaned = ClipboardCleaners.cleanURL(dirty)
        XCTAssertNotNil(cleaned)
        XCTAssertFalse(cleaned!.contains("gclid"))
    }

    func testCleanURL_preservesNonTrackingParams() {
        let dirty = "https://shop.example.com/product?id=42&utm_source=google&category=tech"
        let cleaned = ClipboardCleaners.cleanURL(dirty)
        XCTAssertNotNil(cleaned)
        XCTAssertTrue(cleaned!.contains("id=42"))
        XCTAssertTrue(cleaned!.contains("category=tech"))
        XCTAssertFalse(cleaned!.contains("utm_source"))
    }

    func testCleanURL_returnsNilForCleanURL() {
        let clean = "https://example.com/page?id=42&version=2"
        XCTAssertNil(ClipboardCleaners.cleanURL(clean))
    }

    func testCleanURL_returnsNilForURLWithNoParams() {
        let noParams = "https://example.com/about"
        XCTAssertNil(ClipboardCleaners.cleanURL(noParams))
    }

    func testCleanURL_returnsNilForNonURL() {
        let notAURL = "just some text"
        XCTAssertNil(ClipboardCleaners.cleanURL(notAURL))
    }

    func testCleanURL_stripsAllTrackingLeavingNoQuery() {
        let allTracking = "https://example.com/?utm_source=a&utm_medium=b&fbclid=c"
        let cleaned = ClipboardCleaners.cleanURL(allTracking)
        XCTAssertNotNil(cleaned)
        // When all params are stripped the query string should be absent
        XCTAssertFalse(cleaned!.contains("?"))
    }

    func testCleanURL_handlesMultipleUtmVariants() {
        let dirty = "https://example.com/?utm_id=123&utm_reader=rss&utm_content=hero"
        let cleaned = ClipboardCleaners.cleanURL(dirty)
        XCTAssertNotNil(cleaned)
        XCTAssertFalse(cleaned!.contains("utm_"))
    }

    // MARK: - prettyJSON

    func testPrettyJSON_formatsObject() {
        let compact = #"{"a":1,"b":[2,3]}"#
        let pretty = ClipboardCleaners.prettyJSON(compact)
        XCTAssertNotNil(pretty)
        // Pretty output must contain newlines
        XCTAssertTrue(pretty!.contains("\n"))
    }

    func testPrettyJSON_sortsKeys() {
        let json = #"{"z":3,"a":1,"m":2}"#
        let pretty = ClipboardCleaners.prettyJSON(json)
        XCTAssertNotNil(pretty)
        // "a" must appear before "m" and "z" in the output
        let aIndex = pretty!.range(of: "\"a\"")!.lowerBound
        let mIndex = pretty!.range(of: "\"m\"")!.lowerBound
        let zIndex = pretty!.range(of: "\"z\"")!.lowerBound
        XCTAssertLessThan(aIndex, mIndex)
        XCTAssertLessThan(mIndex, zIndex)
    }

    func testPrettyJSON_formatsArray() {
        let compact = #"[{"id":1},{"id":2}]"#
        let pretty = ClipboardCleaners.prettyJSON(compact)
        XCTAssertNotNil(pretty)
        XCTAssertTrue(pretty!.contains("\n"))
    }

    func testPrettyJSON_returnsNilForInvalidJSON() {
        let invalid = #"{"broken: true"#
        XCTAssertNil(ClipboardCleaners.prettyJSON(invalid))
    }

    func testPrettyJSON_returnsNilForPlainText() {
        XCTAssertNil(ClipboardCleaners.prettyJSON("hello world"))
    }

    // MARK: - decodeBase64

    func testDecodeBase64_returnsValidUTF8ForValidInput() {
        // "Hello, OllamaBob!" base64-encoded
        let encoded = "SGVsbG8sIE9sbGFtYUJvYiE="
        let decoded = ClipboardCleaners.decodeBase64(encoded)
        XCTAssertEqual(decoded, "Hello, OllamaBob!")
    }

    func testDecodeBase64_returnsNilForInvalidBase64() {
        let invalid = "this is not base64!!!"
        // Should return nil because Data(base64Encoded:) fails or UTF-8 decode fails
        let result = ClipboardCleaners.decodeBase64(invalid)
        // Either nil (decode failed) or some garbage — but the content won't be
        // the original string. We assert nil because "!!!" is not valid base64.
        XCTAssertNil(result)
    }

    func testDecodeBase64_returnsNilForBinaryBlob() {
        // Base64 that decodes to non-UTF-8 bytes (raw binary)
        // 0xFF 0xFE 0xFD (invalid UTF-8 sequence)
        let binaryB64 = Data([0xFF, 0xFE, 0xFD]).base64EncodedString()
        let result = ClipboardCleaners.decodeBase64(binaryB64)
        XCTAssertNil(result)
    }

    func testDecodeBase64_handlesURLSafeVariant() {
        // URL-safe base64 uses - and _ instead of + and /
        // Encode "Hello World" the normal way, then convert to URL-safe
        let normal = "SGVsbG8gV29ybGQ="
        let urlSafe = normal.replacingOccurrences(of: "+", with: "-")
                            .replacingOccurrences(of: "/", with: "_")
        let decoded = ClipboardCleaners.decodeBase64(urlSafe)
        XCTAssertEqual(decoded, "Hello World")
    }

    func testDecodeBase64_trimsWhitespace() {
        let padded = "  SGVsbG8gV29ybGQ=  "
        let decoded = ClipboardCleaners.decodeBase64(padded)
        XCTAssertEqual(decoded, "Hello World")
    }
}
