import XCTest
@testable import OllamaBob

/// Tests for `ClipboardClassifier`.
///
/// All tests exercise pure logic — no NSPasteboard access.
final class ClipboardClassifierTests: XCTestCase {

    // MARK: - messyURL

    func testURLWithUtmSource_classifiesAsMessyURL() {
        let url = "https://example.com/blog?utm_source=newsletter&utm_medium=email"
        XCTAssertEqual(ClipboardClassifier.classify(url), .messyURL)
    }

    func testURLWithFbclid_classifiesAsMessyURL() {
        let url = "https://www.facebook.com/share?fbclid=IwAR0abc123"
        XCTAssertEqual(ClipboardClassifier.classify(url), .messyURL)
    }

    func testURLWithGclid_classifiesAsMessyURL() {
        let url = "https://example.com/?gclid=Cj0KCQjwxyz&q=test"
        XCTAssertEqual(ClipboardClassifier.classify(url), .messyURL)
    }

    func testURLWithMultipleTrackingParams_classifiesAsMessyURL() {
        let url = "https://shop.example.com/product?id=42&utm_source=google&utm_campaign=spring"
        XCTAssertEqual(ClipboardClassifier.classify(url), .messyURL)
    }

    func testCleanURL_returnsNil() {
        let url = "https://example.com/page?id=42&category=tech"
        XCTAssertNil(ClipboardClassifier.classify(url))
    }

    func testURLWithNoQuery_returnsNil() {
        let url = "https://example.com/about"
        XCTAssertNil(ClipboardClassifier.classify(url))
    }

    // MARK: - messyJSON

    func testCompactJSONObject_classifiesAsMessyJSON() {
        let json = #"{"a":1,"b":[2,3]}"#
        XCTAssertEqual(ClipboardClassifier.classify(json), .messyJSON)
    }

    func testJSONArray_classifiesAsMessyJSON() {
        let json = #"[{"id":1},{"id":2}]"#
        XCTAssertEqual(ClipboardClassifier.classify(json), .messyJSON)
    }

    func testNestedJSON_classifiesAsMessyJSON() {
        let json = #"{"name":"Bob","meta":{"version":"1.0","enabled":true}}"#
        XCTAssertEqual(ClipboardClassifier.classify(json), .messyJSON)
    }

    func testInvalidJSON_doesNotClassifyAsMessyJSON() {
        let notJson = #"{"broken: true"#
        // Should not be .messyJSON since it doesn't parse
        let result = ClipboardClassifier.classify(notJson)
        XCTAssertNotEqual(result, .messyJSON)
    }

    // MARK: - base64Blob

    func testLongBase64String_classifiesAsBase64Blob() {
        // 88-char valid base64 string (encodes 66 bytes)
        let b64 = "SGVsbG8gV29ybGQhIFRoaXMgaXMgYSBsb25nIGJhc2U2NCBlbmNvZGVkIHN0cmluZyBmb3IgdGVzdGluZw=="
        XCTAssertEqual(ClipboardClassifier.classify(b64), .base64Blob)
    }

    func testShortBase64TooShort_returnsNil() {
        // Under 64 chars — should not classify as base64
        let short = "SGVsbG8="
        XCTAssertNil(ClipboardClassifier.classify(short))
    }

    func testBase64WithSpaces_doesNotClassifyAsBase64Blob() {
        // base64 with whitespace (multi-line PEM-style) is not a blob
        let pem = "SGVsbG8g V29ybGQhIFRoaXMgaXMgYSBsb25nIGJhc2U2NCBlbmNvZGVkIHN0cmlu"
        XCTAssertNotEqual(ClipboardClassifier.classify(pem), .base64Blob)
    }

    // MARK: - stackTrace

    func testJavaScriptStackTrace_classifiesAsStackTrace() {
        let trace = """
Error: Something went wrong
    at Object.handleError (app.js:42:5)
    at processRequest (server.js:100:3)
    at Layer.handle [as handle_request] (express/lib/router/layer.js:95:5)
    at next (express/lib/router/route.js:137:13)
"""
        XCTAssertEqual(ClipboardClassifier.classify(trace), .stackTrace)
    }

    func testJVMStackTrace_classifiesAsStackTrace() {
        let trace = """
java.lang.NullPointerException
    at com.example.Foo.bar(Foo.java:42)
    at com.example.Main.run(Main.java:17)
    at com.example.App.main(App.java:8)
"""
        XCTAssertEqual(ClipboardClassifier.classify(trace), .stackTrace)
    }

    func testPythonStackTrace_classifiesAsStackTrace() {
        let trace = """
Traceback (most recent call last):
  File "app.py", line 42, in main
  File "utils.py", line 17, in process
  File "core.py", line 8, in run
RuntimeError: something failed
"""
        XCTAssertEqual(ClipboardClassifier.classify(trace), .stackTrace)
    }

    func testTooFewStackLines_doesNotClassify() {
        // Only 2 matching stack lines — below the 3-line threshold
        let trace = """
Error: oops
    at foo (bar.js:1:1)
    at baz (qux.js:2:1)
"""
        // 2 matching lines is not enough — should return nil or non-stackTrace
        let result = ClipboardClassifier.classify(trace)
        XCTAssertNotEqual(result, .stackTrace)
    }

    // MARK: - Plain prose → nil

    func testPlainProse_returnsNil() {
        let prose = "Hello, this is just some ordinary text without any special encoding or structure."
        XCTAssertNil(ClipboardClassifier.classify(prose))
    }

    func testEmptyString_returnsNil() {
        XCTAssertNil(ClipboardClassifier.classify(""))
    }

    func testWhitespaceOnly_returnsNil() {
        XCTAssertNil(ClipboardClassifier.classify("   \n\t  "))
    }

    func testShortWord_returnsNil() {
        XCTAssertNil(ClipboardClassifier.classify("hello"))
    }

    // MARK: - URL without tracking params → nil

    func testURLWithOnlyCleanParams_returnsNil() {
        let url = "https://docs.example.com/api?version=2&format=json"
        XCTAssertNil(ClipboardClassifier.classify(url))
    }
}
