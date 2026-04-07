import AppKit

enum ApprovalAlert {
    /// Show a blocking NSAlert for command approval. Must be called on main thread.
    @MainActor
    static func show(command: String, toolName: String, level: ApprovalLevel) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Approve Action?"
        alert.informativeText = "Bob wants to run:\n\n\(command)\n\nTool: \(toolName)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Approve")
        alert.addButton(withTitle: "Deny")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
