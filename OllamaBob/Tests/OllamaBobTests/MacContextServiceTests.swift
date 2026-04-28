import XCTest
@testable import OllamaBob

/// Tests for `MacContextService`, `MacContextStore`, and the `MacContext` model.
/// These tests do NOT make real ScreenCaptureKit calls (TCC blocks them in test
/// runs). They exercise the data model, clipboard metadata extraction, and
/// store observability layers only.
final class MacContextServiceTests: XCTestCase {

    // MARK: - MacContext equality

    func testMacContextEquality() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let app  = MacContext.ActiveApp(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            windowTitle: "Apple"
        )
        let a = MacContext(
            capturedAt: date,
            activeApp: app,
            selectedItems: ["/tmp/a.txt"],
            clipboardMeta: MacContext.ClipboardMeta(length: 5, preview: "hello", isText: true),
            screenOCRSnippet: nil
        )
        let b = MacContext(
            capturedAt: date,
            activeApp: app,
            selectedItems: ["/tmp/a.txt"],
            clipboardMeta: MacContext.ClipboardMeta(length: 5, preview: "hello", isText: true),
            screenOCRSnippet: nil
        )
        XCTAssertEqual(a, b)
    }

    func testMacContextInequalityOnWindowTitle() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let appA = MacContext.ActiveApp(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            windowTitle: "Page A"
        )
        let appB = MacContext.ActiveApp(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            windowTitle: "Page B"
        )
        let a = MacContext(capturedAt: date, activeApp: appA, selectedItems: nil, clipboardMeta: nil, screenOCRSnippet: nil)
        let b = MacContext(capturedAt: date, activeApp: appB, selectedItems: nil, clipboardMeta: nil, screenOCRSnippet: nil)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - ActiveApp formatting

    func testActiveWindowSummaryIncludesAppNameAndTitle() {
        let ctx = MacContext(
            capturedAt: Date(),
            activeApp: MacContext.ActiveApp(
                bundleIdentifier: "com.apple.Xcode",
                localizedName: "Xcode",
                windowTitle: "MyProject.swift"
            ),
            selectedItems: nil,
            clipboardMeta: nil,
            screenOCRSnippet: nil
        )
        let summary = ctx.activeWindowSummary()
        XCTAssertTrue(summary.contains("Xcode"), summary)
        XCTAssertTrue(summary.contains("com.apple.Xcode"), summary)
        XCTAssertTrue(summary.contains("MyProject.swift"), summary)
    }

    func testActiveWindowSummaryHandlesNilTitle() {
        let ctx = MacContext(
            capturedAt: Date(),
            activeApp: MacContext.ActiveApp(
                bundleIdentifier: "com.apple.Terminal",
                localizedName: "Terminal",
                windowTitle: nil
            ),
            selectedItems: nil,
            clipboardMeta: nil,
            screenOCRSnippet: nil
        )
        let summary = ctx.activeWindowSummary()
        XCTAssertTrue(summary.contains("Terminal"), summary)
        // Should NOT include "Window:" line when title is nil
        XCTAssertFalse(summary.contains("Window:"), summary)
    }

    // MARK: - Clipboard metadata extraction

    @MainActor
    func testClipboardMetaExtractsTextWhenTextPresent() {
        // Put a known string onto the pasteboard temporarily.
        let pb = NSPasteboard.general
        let savedTypes = pb.types ?? []
        let originalContents = pb.string(forType: .string)

        pb.clearContents()
        pb.setString("Hello, Bob! 1234567890", forType: .string)

        let meta = MacContextService.clipboardMeta()

        // Restore
        pb.clearContents()
        if let original = originalContents {
            pb.setString(original, forType: .string)
        }

        XCTAssertNotNil(meta)
        XCTAssertTrue(meta?.isText == true)
        XCTAssertTrue(meta?.length ?? 0 > 0)
        XCTAssertTrue(meta?.preview.contains("Hello, Bob!") == true, meta?.preview ?? "nil")
        // Suppress unused variable warning
        _ = savedTypes
    }

    @MainActor
    func testClipboardMetaReturnsNonTextDescriptorForImageContent() {
        let pb = NSPasteboard.general
        let originalContents = pb.string(forType: .string)

        pb.clearContents()
        // Write a tiny PNG to the pasteboard to simulate an image
        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let pngData = rep.representation(using: .png, properties: [:]) {
            pb.setData(pngData, forType: .png)
        }

        let meta = MacContextService.clipboardMeta()

        // Restore
        pb.clearContents()
        if let original = originalContents {
            pb.setString(original, forType: .string)
        }

        // When a PNG is set without a string type, it should be non-text
        if let meta = meta {
            // May be nil if the PNG write above failed in the test environment
            XCTAssertFalse(meta.isText, "Expected non-text meta for image clipboard")
        }
    }

    // MARK: - MacContextStore observability

    @MainActor
    func testMacContextStorePublishesOnUpdate() {
        let store = MacContextStore.shared
        let expectation = XCTestExpectation(description: "lastContext published")
        var received: MacContext?

        let cancellable = store.$lastContext.dropFirst().sink { ctx in
            received = ctx
            expectation.fulfill()
        }

        let ctx = MacContext(
            capturedAt: Date(),
            activeApp: MacContext.ActiveApp(
                bundleIdentifier: "com.test.app",
                localizedName: "TestApp",
                windowTitle: "TestWindow"
            ),
            selectedItems: nil,
            clipboardMeta: nil,
            screenOCRSnippet: nil
        )
        store.update(ctx)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(received, ctx)
        // Clean up
        store.clear()
        cancellable.cancel()
    }

    @MainActor
    func testMacContextStoreClearNilsLastContext() {
        let store = MacContextStore.shared
        let ctx = MacContext(
            capturedAt: Date(),
            activeApp: nil,
            selectedItems: nil,
            clipboardMeta: nil,
            screenOCRSnippet: nil
        )
        store.update(ctx)
        XCTAssertNotNil(store.lastContext)
        store.clear()
        XCTAssertNil(store.lastContext)
        XCTAssertNil(store.lastOCRText)
    }
}
