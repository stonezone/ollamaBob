import SwiftUI
import AppKit

struct MemoryIOPanel: View {

    private static let phosphorGreen = Color(red: 0.22, green: 1.0,  blue: 0.08)
    private static let bgPanel       = Color(red: 0.10, green: 0.11, blue: 0.10)
    private static let textGrey      = Color(white: 0.50)

    var onImportComplete: (() -> Void)?

    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool   = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                exportButton
                importButton
            }
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(statusIsError
                        ? .orange
                        : MemoryIOPanel.phosphorGreen.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemoryIOPanel.bgPanel)
    }

    private var exportButton: some View {
        Button(action: handleExport) {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(MemoryIOPanel.phosphorGreen)
        }
        .buttonStyle(.plain)
        .help("Export all memory facts to a Markdown file")
    }

    private var importButton: some View {
        Button(action: handleImport) {
            Label("Import", systemImage: "square.and.arrow.down")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(MemoryIOPanel.phosphorGreen)
        }
        .buttonStyle(.plain)
        .help("Import memory facts from a Markdown file")
    }

    private func handleExport() {
        let markdown: String
        do {
            markdown = try DatabaseManager.shared.exportFactsMarkdown()
        } catch {
            setStatus("Export failed: \(error.localizedDescription)", isError: true)
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export memory facts"
        panel.nameFieldStringValue = "ollamabob-memory.md"
        panel.allowedContentTypes = [.text]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            setStatus("Exported to \(url.lastPathComponent)", isError: false)
        } catch {
            setStatus("Write failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func handleImport() {
        let panel = NSOpenPanel()
        panel.title = "Import memory facts"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.text]
        panel.message = "Choose a Markdown file exported by OllamaBob"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            setStatus("Read failed: \(error.localizedDescription)", isError: true)
            return
        }

        do {
            let count = try DatabaseManager.shared.importFactsMarkdown(text)
            setStatus("Imported \(count) fact\(count == 1 ? "" : "s")", isError: false)
            onImportComplete?()
        } catch {
            setStatus("Import failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
