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

protocol BrowserActivating {
    func activateBrowser(for url: URL)
}

struct DefaultBrowserActivator: BrowserActivating {
    func activateBrowser(for url: URL) {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url),
              let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            for app in runningApps {
                _ = app.activate(options: [.activateAllWindows])
            }
        }
    }
}

enum ExternalURLPresenter {
    @discardableResult
    static func open(
        _ url: URL,
        workspace: WorkspaceOpening,
        browserActivator: BrowserActivating
    ) -> Bool {
        guard workspace.open(url) else {
            return false
        }
        browserActivator.activateBrowser(for: url)
        return true
    }
}

@MainActor
final class PresentationService: ObservableObject {
    static let shared = PresentationService()

    let richHTMLState: RichHTMLState

    private let workspace: WorkspaceOpening
    private let browserActivator: BrowserActivating
    private var openRichHTMLWindowHandler: (() -> Void)?

    init(
        workspace: WorkspaceOpening,
        richHTMLState: RichHTMLState,
        browserActivator: BrowserActivating = DefaultBrowserActivator()
    ) {
        self.workspace = workspace
        self.richHTMLState = richHTMLState
        self.browserActivator = browserActivator
    }

    convenience init(
        workspace: WorkspaceOpening = NSWorkspace.shared,
        browserActivator: BrowserActivating = DefaultBrowserActivator()
    ) {
        self.init(
            workspace: workspace,
            richHTMLState: RichHTMLState(),
            browserActivator: browserActivator
        )
    }

    func registerOpenRichHTMLWindow(_ handler: @escaping () -> Void) {
        openRichHTMLWindowHandler = handler
    }

    @discardableResult
    func reopenHTML(id: String) throws -> String {
        // Rich HTML presentations are stored in RichHTMLState by a stable
        // presentation id so transcript chips can reopen the same document
        // after the companion window has been closed.
        guard AppSettings.shared.richPresentationEnabled else {
            throw PresentationError.richPresentationDisabled
        }
        guard let openRichHTMLWindowHandler else {
            throw PresentationError.richWindowUnavailable
        }
        guard richHTMLState.activatePresentation(id: id) else {
            throw PresentationError.openFailed(id)
        }
        openRichHTMLWindowHandler()
        return "Reopened rich view: \(richHTMLState.title)"
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
        let document = Self.injectDocumentDefaults(
            into: sanitized,
            allowRemoteResources: AppSettings.shared.richPresentationRemoteResourcesEnabled
        )
        richHTMLState.html = document
        _ = richHTMLState.storePresentation(title: effectiveTitle, html: document)
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
        guard ExternalURLPresenter.open(url, workspace: workspace, browserActivator: browserActivator) else {
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
            #"(?is)<meta\b[^>]*http-equiv\s*=\s*['"]?refresh['"]?[^>]*>"#,
            #"(?is)\son[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#,
            #"(?is)[/\s](?:on[a-z]+)\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#,
            #"(?is)\s(?:href|src|data|poster)\s*=\s*(['"])\s*(?:javascript|vbscript):.*?\1"#,
            #"(?is)\s(?:href|src|data|poster)\s*=\s*(?:javascript|vbscript):[^\s>]+"#,
            #"(?is)\s(?:href|src|data|poster)\s*=\s*(['"])\s*data:(?!image/).*?\1"#,
            #"(?is)\s(?:href|src|data|poster)\s*=\s*data:(?!image/)[^\s>]+"#
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
            #"(?is)<embed\b[^>]*\bsrc\s*=\s*['"]https?://[^'"]+['"][^>]*>"#,
            #"(?is)<(?:img|link|source|iframe|audio|video|object|embed)\b[^>]*\b(?:src|href|data)\s*=\s*https?://[^\s>]+[^>]*>"#,
            #"(?is)\ssrcset\s*=\s*['"][^'"]*https?://[^'"]*['"]"#,
            #"(?is)\ssrcset\s*=\s*https?://[^\s>]+"#,
            #"(?is)<style\b[^>]*>.*?(?:@import\s+['"]https?://|url\(\s*['"]?https?://).*?</style>"#
        ]
        for pattern in remotePatterns {
            sanitized = stripMatches(pattern: pattern, in: sanitized)
        }
        return sanitized
    }

    static func injectDocumentDefaults(into html: String, allowRemoteResources: Bool) -> String {
        let defaults = documentDefaults(allowRemoteResources: allowRemoteResources)

        if let headRange = html.range(of: #"<head\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
            var document = html
            document.insert(contentsOf: "\n\(defaults)\n", at: headRange.upperBound)
            return document
        }

        if let htmlRange = html.range(of: #"<html\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
            var document = html
            document.insert(contentsOf: "\n<head>\n\(defaults)\n</head>\n", at: htmlRange.upperBound)
            return document
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        \(defaults)
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }

    private static func documentDefaults(allowRemoteResources: Bool) -> String {
        let contentSecurityPolicy: String
        if allowRemoteResources {
            contentSecurityPolicy = "default-src 'none'; img-src https: data: file:; style-src 'unsafe-inline' https:; font-src https: data:; connect-src https:; media-src https: data: file:; object-src 'none'; frame-src https:;"
        } else {
            contentSecurityPolicy = "default-src 'none'; img-src data: file:; style-src 'unsafe-inline'; font-src data: file:; connect-src 'none'; media-src data: file:; object-src 'none'; frame-src 'none';"
        }

        return """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <style>
        :root { color-scheme: light dark; }
        html, body {
          margin: 0;
          padding: 0;
          background: transparent;
          color: CanvasText;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          line-height: 1.5;
        }
        body {
          padding: 20px 24px;
        }
        a {
          color: LinkText;
        }
        img, video {
          max-width: 100%;
          height: auto;
        }
        pre, code {
          font-family: "SF Mono", Menlo, Monaco, monospace;
        }
        </style>
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
