import Foundation

/// A snapshot of the user's current Mac context captured at a point in time.
/// Contains the frontmost app, Finder selection, clipboard metadata, and
/// an optional OCR snippet from the last screen capture. All fields are
/// optional because any one of them may be unavailable (app not scriptable,
/// Finder not frontmost, clipboard empty or non-text, screen capture denied).
struct MacContext: Equatable, Sendable {
    let capturedAt: Date

    /// The frontmost app at capture time.
    let activeApp: ActiveApp?

    /// Paths selected in Finder at capture time. `nil` if Finder was not
    /// frontmost or the selection was empty. Bounded to 50 paths.
    let selectedItems: [String]?

    /// Clipboard metadata captured at the same time. Does NOT include the
    /// full clipboard contents — just length, a short preview, and a flag
    /// indicating whether the clipboard holds text at all.
    let clipboardMeta: ClipboardMeta?

    /// First 500 characters of the last OCR run, when the window hasn't
    /// changed since the OCR was performed. Intended for the ContextChipView
    /// display only; the full OCR result is returned by `screen_ocr` directly.
    let screenOCRSnippet: String?

    // MARK: - Nested types

    struct ActiveApp: Equatable, Sendable {
        let bundleIdentifier: String
        let localizedName: String
        /// The frontmost window title, if accessible via Accessibility APIs or
        /// NSWorkspace. May be nil for apps that don't expose a window title.
        let windowTitle: String?
    }

    struct ClipboardMeta: Equatable, Sendable {
        /// UTF-8 byte length of the clipboard string, or 0 for non-text.
        let length: Int
        /// First 200 characters of the clipboard string, or a descriptor
        /// like "(non-text content: public.tiff)" for images/files.
        let preview: String
        /// True when the clipboard holds a plain-text string type.
        let isText: Bool
    }
}

// MARK: - Formatting helpers

extension MacContext {
    /// A human-readable summary suitable for use as a tool result payload.
    /// Does NOT include screen OCR (that is returned by `screen_ocr` directly).
    func currentContextSummary() -> String {
        var lines: [String] = []
        lines.append("Captured at: \(formattedTime(capturedAt))")

        if let app = activeApp {
            var appLine = "Active app: \(app.localizedName) (\(app.bundleIdentifier))"
            if let title = app.windowTitle, !title.isEmpty {
                appLine += " — \"\(title)\""
            }
            lines.append(appLine)
        } else {
            lines.append("Active app: (unknown)")
        }

        if let items = selectedItems, !items.isEmpty {
            lines.append("Finder selection (\(items.count) item\(items.count == 1 ? "" : "s")):")
            for item in items {
                lines.append("  \(item)")
            }
        } else {
            lines.append("Finder selection: (none)")
        }

        if let meta = clipboardMeta {
            if meta.isText {
                let preview = meta.preview.isEmpty ? "(empty string)" : meta.preview
                lines.append("Clipboard: \(meta.length) chars — \(preview)")
            } else {
                lines.append("Clipboard: \(meta.preview)")
            }
        } else {
            lines.append("Clipboard: (empty or unavailable)")
        }

        return lines.joined(separator: "\n")
    }

    /// A summary for the `active_window` tool: just the app + window title.
    func activeWindowSummary() -> String {
        guard let app = activeApp else {
            return "No frontmost application detected."
        }
        var parts = ["App: \(app.localizedName) (\(app.bundleIdentifier))"]
        if let title = app.windowTitle, !title.isEmpty {
            parts.append("Window: \"\(title)\"")
        }
        parts.append("Captured at: \(formattedTime(capturedAt))")
        return parts.joined(separator: "\n")
    }

    private func formattedTime(_ date: Date) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let s = cal.component(.second, from: date)
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
