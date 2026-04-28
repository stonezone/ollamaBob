import Foundation
import AppKit
import SwiftSoup

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

    /// Pre-WebView allowlist sanitizer. Defense-in-depth layer #1.
    ///
    /// Parses the input as HTML with SwiftSoup, drops dangerous element types
    /// outright, walks every remaining element to strip `on*` event handlers,
    /// neutralize dangerous URL schemes (`javascript:`, `vbscript:`, non-image
    /// `data:`) on URL-bearing attributes, and clean inline `style` attributes
    /// of `expression(...)`, `behavior:`, `@import`, and remote `url(...)`
    /// when `allowRemoteResources == false`.
    ///
    /// Bumping `AppConfig.htmlSanitizerVersion` is the contract for material
    /// rule changes here. Backstops in `RichHTMLView` (CSP, JS disabled,
    /// navigation blocking) are independent and intentionally redundant.
    /// On parse failure: returns empty string (fail-closed).
    static func sanitizeHTML(_ html: String, allowRemoteResources: Bool) -> String {
        do {
            let document = try SwiftSoup.parse(html)

            // Drop dangerous element types entirely. These are removed even
            // when their attributes look clean — their presence alone is the
            // attack vector.
            try document.select(
                "script, style, iframe, object, embed, form, input, button, base, meta, link, applet, frame, frameset, noscript"
            ).remove()

            // Walk every element and clean attributes.
            for element in try document.getAllElements() {
                guard let attributes = element.getAttributes() else { continue }
                // Snapshot because we mutate during iteration.
                let snapshot = attributes.asList()
                for attribute in snapshot {
                    let key = attribute.getKey()
                    let lowerKey = key.lowercased()
                    let rawValue = attribute.getValue()
                    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

                    // 1. Strip ALL on* event handlers regardless of tag.
                    if lowerKey.hasPrefix("on") {
                        try element.removeAttr(key)
                        continue
                    }

                    // 2. URL-bearing attributes: drop if dangerous scheme or
                    //    remote URL when remote resources are disallowed.
                    if Self.urlBearingAttributeKeys.contains(lowerKey) {
                        if Self.urlIsDangerous(value, allowRemoteResources: allowRemoteResources) {
                            try element.removeAttr(key)
                            continue
                        }
                    }

                    // 3. srcset is comma-separated; reject the whole attribute
                    //    if any candidate URL is dangerous.
                    if lowerKey == "srcset" {
                        if Self.srcsetContainsDangerousURL(value, allowRemoteResources: allowRemoteResources) {
                            try element.removeAttr(key)
                            continue
                        }
                    }

                    // 4. Inline style: drop the attribute wholesale if a
                    //    known XSS vector is present. Leaves benign styles intact.
                    if lowerKey == "style" {
                        if Self.styleIsDangerous(value, allowRemoteResources: allowRemoteResources) {
                            try element.removeAttr(key)
                            continue
                        }
                    }
                }
            }

            // Re-render as a body fragment so we don't re-emit synthesized
            // <html><head>... wrappers that SwiftSoup adds when parsing
            // partial input.
            let outputSettings = OutputSettings()
            outputSettings.indentAmount(indentAmount: 0)
            outputSettings.prettyPrint(pretty: false)
            document.outputSettings(outputSettings)

            if let body = document.body() {
                return try body.html()
            }
            return try document.html()
        } catch {
            // Fail closed. The caller still wraps the result with
            // injectDocumentDefaults (CSP) and renders it in a JS-disabled
            // WKWebView, so even an empty string is safe.
            return ""
        }
    }

    private static let urlBearingAttributeKeys: Set<String> = [
        "href", "src", "poster", "data", "action", "formaction",
        "background", "cite", "longdesc", "usemap", "ping",
        "manifest", "archive", "codebase", "classid"
    ]

    private static func urlIsDangerous(_ value: String, allowRemoteResources: Bool) -> Bool {
        let lower = value.lowercased()
        if lower.hasPrefix("javascript:") || lower.hasPrefix("vbscript:") {
            return true
        }
        if lower.hasPrefix("data:") {
            // Allow data:image/* only. Block data:text/html, data:application/*, etc.
            if lower.hasPrefix("data:image/") == false {
                return true
            }
        }
        if !allowRemoteResources {
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
                return true
            }
        }
        return false
    }

    private static func srcsetContainsDangerousURL(_ value: String, allowRemoteResources: Bool) -> Bool {
        let segments = value.split(separator: ",")
        for raw in segments {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // First whitespace-separated token is the URL; the rest is descriptor (1x, 200w, etc).
            let firstToken = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            if urlIsDangerous(firstToken, allowRemoteResources: allowRemoteResources) {
                return true
            }
        }
        return false
    }

    private static func styleIsDangerous(_ style: String, allowRemoteResources: Bool) -> Bool {
        let lower = style.lowercased()
        // Legacy IE-era XSS that some renderers still honor.
        if lower.contains("expression(") { return true }
        if lower.contains("behavior:") { return true }
        // CSS @import can fetch remote stylesheets.
        if lower.contains("@import") { return true }
        if !allowRemoteResources {
            // Cover quoted and unquoted url() forms.
            if lower.contains("url(http://") || lower.contains("url(https://") { return true }
            if lower.contains("url('http://") || lower.contains("url('https://") { return true }
            if lower.contains("url(\"http://") || lower.contains("url(\"https://") { return true }
        }
        return false
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

}
