import AppKit

enum ApprovalAlert {

    /// Sentinel used to carry an optional unified-diff payload through the
    /// `ApprovalHandler` `command` string without changing the handler signature.
    /// `describeToolCall` appends this separator + the diff text when a non-empty
    /// diff exists.  `show` splits on the first occurrence and renders the tail
    /// in a scrollable mono-font NSTextView accessory view.
    static let diffSeparator = "\n\n--- WRITE_FILE DIFF ---\n"

    /// Show a blocking NSAlert for command approval. Must be called on main thread.
    @MainActor
    static func show(command: String, toolName: String, level: ApprovalLevel) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Approve Action?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Approve")
        alert.addButton(withTitle: "Deny")

        // Split on the first occurrence of the diff separator.
        if let separatorRange = command.range(of: diffSeparator) {
            let head = String(command[command.startIndex..<separatorRange.lowerBound])
            let diffText = String(command[separatorRange.upperBound...])

            alert.informativeText = "Bob wants to run:\n\n\(head)\n\nTool: \(toolName)"

            if !diffText.isEmpty {
                alert.accessoryView = makeDiffScrollView(diffText: diffText)
            }
        } else {
            alert.informativeText = "Bob wants to run:\n\n\(command)\n\nTool: \(toolName)"
        }

        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Private helpers

    @MainActor
    private static func makeDiffScrollView(diffText: String) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = diffText
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        // Allow horizontal scrolling — disable word-wrap
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        scrollView.documentView = textView
        return scrollView
    }
}
