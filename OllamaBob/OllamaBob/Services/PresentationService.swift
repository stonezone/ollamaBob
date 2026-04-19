import Foundation
import AppKit

@MainActor
enum PresentationKind: String, CaseIterable, Sendable {
    case html
    case url
    case file
}

enum PresentationError: LocalizedError, Equatable {
    case richPresentationDisabled
    case htmlEmpty
    case urlMalformed
    case urlSchemeNotAllowed
    case fileNotFound(String)
    case pathNotAllowed(String)
    case richWindowUnavailable
    case openFailed(String)

    var errorDescription: String? {
        switch self {
        case .richPresentationDisabled:
            return "rich presentation disabled"
        case .htmlEmpty:
            return "html empty"
        case .urlMalformed:
            return "url malformed"
        case .urlSchemeNotAllowed:
            return "url scheme not allowed"
        case .fileNotFound:
            return "file not found"
        case .pathNotAllowed:
            return "path not allowed"
        case .richWindowUnavailable:
            return "rich html window unavailable"
        case .openFailed:
            return "could not open target"
        }
    }
}

protocol WorkspaceOpening {
    @discardableResult
    func open(_ url: URL) -> Bool
}

extension NSWorkspace: WorkspaceOpening {}

@MainActor
final class PresentationService: ObservableObject {
    static let shared = PresentationService()

    let richHTMLState: RichHTMLState

    private let workspace: WorkspaceOpening
    private var openRichHTMLWindowHandler: (() -> Void)?

    init(
        workspace: WorkspaceOpening,
        richHTMLState: RichHTMLState
    ) {
        self.workspace = workspace
        self.richHTMLState = richHTMLState
    }

    convenience init(workspace: WorkspaceOpening = NSWorkspace.shared) {
        self.init(workspace: workspace, richHTMLState: RichHTMLState())
    }

    func registerOpenRichHTMLWindow(_ handler: @escaping () -> Void) {
        openRichHTMLWindowHandler = handler
    }

    @discardableResult
    func present(kind: PresentationKind, content: String, title: String? = nil) throws -> String {
        guard AppSettings.shared.richPresentationEnabled else {
            throw PresentationError.richPresentationDisabled
        }

        switch kind {
        case .html:
            return try presentHTML(content, title: title)
        case .url:
            return try presentURL(content)
        case .file:
            return try presentFile(content)
        }
    }

    private func presentHTML(_ content: String, title: String?) throws -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw PresentationError.htmlEmpty
        }
        guard let openRichHTMLWindowHandler else {
            throw PresentationError.richWindowUnavailable
        }

        let effectiveTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? title!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "Bob's View"
        let sanitized = Self.sanitizeHTML(
            trimmed,
            allowRemoteResources: AppSettings.shared.richPresentationRemoteResourcesEnabled
        )

        richHTMLState.title = effectiveTitle
        richHTMLState.html = Self.wrapHTMLDocumentIfNeeded(sanitized)
        openRichHTMLWindowHandler()
        return "Opened rich view: \(effectiveTitle)"
    }

    private func presentURL(_ content: String) throws -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            throw PresentationError.urlMalformed
        }
        guard scheme == "http" || scheme == "https" else {
            throw PresentationError.urlSchemeNotAllowed
        }
        guard workspace.open(url) else {
            throw PresentationError.openFailed(trimmed)
        }
        return "Opened URL: \(trimmed)"
    }

    private func presentFile(_ content: String) throws -> String {
        guard let fileURL = FileToolPaths.resolvedURL(for: content) else {
            throw PresentationError.fileNotFound(content)
        }
        guard PathPolicy.check(fileURL.path) == .allowed else {
            throw PresentationError.pathNotAllowed(fileURL.path)
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PresentationError.fileNotFound(fileURL.path)
        }
        guard workspace.open(fileURL) else {
            throw PresentationError.openFailed(fileURL.path)
        }
        return "Opened file: \(fileURL.path)"
    }

    static func sanitizeHTML(_ html: String, allowRemoteResources: Bool) -> String {
        var sanitized = html
        let alwaysStripPatterns = [
            #"(?is)<script\b[^>]*>.*?</script>"#,
            #"(?is)<meta\b[^>]*http-equiv\s*=\s*['"]?refresh['"]?[^>]*>"#
        ]
        for pattern in alwaysStripPatterns {
            sanitized = stripMatches(pattern: pattern, in: sanitized)
        }

        guard allowRemoteResources == false else { return sanitized }

        let remotePatterns = [
            #"(?is)<img\b[^>]*\bsrc\s*=\s*['"]https?://[^'"]+['"][^>]*>"#,
            #"(?is)<link\b[^>]*\bhref\s*=\s*['"]https?://[^'"]+['"][^>]*>"#,
            #"(?is)<source\b[^>]*\bsrc\s*=\s*['"]https?://[^'"]+['"][^>]*>"#,
            #"(?is)<iframe\b[^>]*\bsrc\s*=\s*['"]https?://[^'"]+['"][^>]*>.*?</iframe>"#,
            #"(?is)<audio\b[^>]*\bsrc\s*=\s*['"]https?://[^'"]+['"][^>]*>.*?</audio>"#,
            #"(?is)<video\b[^>]*\bsrc\s*=\s*['"]https?://[^'"]+['"][^>]*>.*?</video>"#,
            #"(?is)<object\b[^>]*\bdata\s*=\s*['"]https?://[^'"]+['"][^>]*>.*?</object>"#,
            #"(?is)<embed\b[^>]*\bsrc\s*=\s*['"]https?://[^'"]+['"][^>]*>"#
        ]
        for pattern in remotePatterns {
            sanitized = stripMatches(pattern: pattern, in: sanitized)
        }
        return sanitized
    }

    static func wrapHTMLDocumentIfNeeded(_ html: String) -> String {
        guard html.range(of: #"<html\b"#, options: [.regularExpression, .caseInsensitive]) == nil else {
            return html
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }

    private static func stripMatches(pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
