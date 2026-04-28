import Foundation

/// Returns the list of currently-selected paths in Finder (max 50).
/// Returns an empty result if Finder is not the frontmost app or if
/// nothing is selected. Read-only, no approval required.
/// Output is wrapped in `<untrusted>` tags because file paths are
/// user-controlled data that could contain injection attempts.
@MainActor
enum SelectedItemsTool {

    private static let maxItems = 50

    static func execute() async -> ToolResult {
        let start = Date()
        let items = await MacContextService.selectedItems()
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        if items.isEmpty {
            return .success(
                tool: "selected_items",
                content: UntrustedWrapper.wrap("No items selected in Finder (or Finder is not frontmost)."),
                durationMs: durationMs
            )
        }

        let capped = Array(items.prefix(maxItems))
        var lines: [String] = ["Selected items in Finder (\(capped.count)):"]
        for path in capped {
            lines.append("  \(path)")
        }
        if items.count > maxItems {
            lines.append("  ... (\(items.count - maxItems) additional items not shown)")
        }
        return .success(
            tool: "selected_items",
            content: UntrustedWrapper.wrap(lines.joined(separator: "\n")),
            durationMs: durationMs
        )
    }
}
