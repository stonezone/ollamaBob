import Foundation
import AppKit
import Vision
import ScreenCaptureKit

/// Static entry point for all Mac context captures. Each method writes its
/// result into `MacContextStore.shared` so the ContextChipView (Phase 8) can
/// observe the latest snapshot without re-calling the service.
///
/// All methods are `@MainActor` because `NSWorkspace` and `NSPasteboard`
/// require the main thread, and `MacContextStore` is also `@MainActor`.
///
/// ScreenCaptureKit is used for screen OCR only; it is called exclusively
/// when the model explicitly invokes the `screen_ocr` tool. There is NO
/// auto-firing or timer-based capture.
@MainActor
enum MacContextService {

    // MARK: - Private constants

    private static let maxOCRChars    = 10_000
    private static let maxSelectedItems = 50
    private static let clipboardPreviewChars = 200

    // MARK: - Public API

    /// Returns the composite "current context": active app + Finder selection
    /// + clipboard metadata. Does NOT capture the screen. Writes to
    /// `MacContextStore.shared`.
    static func currentContext() async -> MacContext {
        let app     = await activeAppInfo()
        let items   = await finderSelection()
        let clip    = clipboardMeta()
        let context = MacContext(
            capturedAt: Date(),
            activeApp: app,
            selectedItems: items.isEmpty ? nil : items,
            clipboardMeta: clip,
            screenOCRSnippet: nil
        )
        MacContextStore.shared.update(context)
        return context
    }

    /// Returns only the frontmost app info + window title. Writes to
    /// `MacContextStore.shared`.
    static func activeWindow() async -> MacContext {
        let app = await activeAppInfo()
        let context = MacContext(
            capturedAt: Date(),
            activeApp: app,
            selectedItems: nil,
            clipboardMeta: nil,
            screenOCRSnippet: nil
        )
        MacContextStore.shared.update(context)
        return context
    }

    /// Returns Finder selection paths (max 50), empty array if Finder is not
    /// frontmost or has nothing selected.
    static func selectedItems() async -> [String] {
        await finderSelection()
    }

    /// Captures the frontmost screen via ScreenCaptureKit and runs Vision OCR.
    /// Returns the extracted text (capped at ~10KB), or `nil` on any error
    /// (TCC denied, no screen, capture failed). On success, writes the text
    /// into `MacContextStore.shared.lastOCRText` as well.
    static func screenOCR() async -> String? {
        guard let cgImage = await captureScreen() else { return nil }
        guard let text = await runOCR(on: cgImage) else { return nil }
        let trimmed = String(text.prefix(maxOCRChars))
        MacContextStore.shared.updateOCR(trimmed)
        return trimmed
    }

    // MARK: - Active window

    private static func activeAppInfo() async -> MacContext.ActiveApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleID    = app.bundleIdentifier ?? "unknown"
        let name        = app.localizedName ?? bundleID
        let windowTitle = await frontWindowTitle(for: app)
        return MacContext.ActiveApp(
            bundleIdentifier: bundleID,
            localizedName: name,
            windowTitle: windowTitle
        )
    }

    /// Attempts to read the frontmost window title for `app` via the
    /// Accessibility API. Returns nil on any error (permission denied, app
    /// doesn't expose accessibility, no windows open, etc.).
    private static func frontWindowTitle(for app: NSRunningApplication) async -> String? {
        let pid = app.processIdentifier
        guard pid > 0 else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              value != nil else {
            // Try frontmost window from window list as fallback
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement],
                  let first = windows.first else {
                return nil
            }
            return axWindowTitle(first)
        }
        // swiftlint:disable:next force_cast
        return axWindowTitle(value as! AXUIElement)
    }

    private static func axWindowTitle(_ element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String,
              !title.isEmpty else {
            return nil
        }
        return title
    }

    // MARK: - Finder selection

    private static func finderSelection() async -> [String] {
        // Use AppleScript to ask Finder for its current selection.
        // This is the canonical way; Accessibility APIs are unreliable for Finder.
        let script = """
        tell application "Finder"
            set sel to selection as alias list
            set pathList to {}
            repeat with f in sel
                set end of pathList to POSIX path of f
            end repeat
            return pathList
        end tell
        """
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return [] }
        let result = appleScript.executeAndReturnError(&error)
        guard error == nil else { return [] }
        // Result is an AppleScript list; iterate the descriptors
        var paths: [String] = []
        let count = result.numberOfItems
        for i in 1...max(count, 1) {
            guard i <= count else { break }
            if let desc = result.atIndex(i), let path = desc.stringValue {
                paths.append(path)
            }
        }
        return Array(paths.prefix(maxSelectedItems))
    }

    // MARK: - Clipboard metadata

    static func clipboardMeta() -> MacContext.ClipboardMeta? {
        let pb = NSPasteboard.general
        if let text = pb.string(forType: .string) {
            let preview = String(text.prefix(clipboardPreviewChars))
            let previewEllipsis = text.count > clipboardPreviewChars ? "…" : ""
            return MacContext.ClipboardMeta(
                length: text.utf8.count,
                preview: preview + previewEllipsis,
                isText: true
            )
        }
        // Check for non-text types
        let allTypes = pb.types ?? []
        if let first = allTypes.first {
            return MacContext.ClipboardMeta(
                length: 0,
                preview: "(non-text content: \(first.rawValue))",
                isText: false
            )
        }
        return nil
    }

    // MARK: - ScreenCaptureKit capture

    private static func captureScreen() async -> CGImage? {
        // SCScreenshotManager requires macOS 14.0+; we target .macOS(.v14)
        // so no availability check is needed. However, TCC denial returns an
        // error rather than crashing, so we catch it and return nil.
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { return nil }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width  = display.width
            config.height = display.height
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return image
        } catch {
            // TCC denied, permission not granted, or hardware failure — all
            // silent. The tool surfaces "Screen OCR unavailable" instead of
            // propagating the error.
            return nil
        }
    }

    // MARK: - Vision OCR

    private static func runOCR(on cgImage: CGImage) async -> String? {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, err in
                guard err == nil,
                      let results = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let lines = results.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if #available(macOS 14.0, *) {
                request.revision = VNRecognizeTextRequestRevision3
            }

            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
