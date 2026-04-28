import SwiftUI
import WebKit
import AppKit

enum RichHTMLNavigationDecision: Equatable {
    case allow
    case cancel
    case openExternal
}

// MARK: - Rich HTML defense-in-depth
//
// `present(kind=html)` renders model-produced HTML inside `WKWebView`. The
// content surface is unsandboxed by macOS standards and the input is
// untrusted, so the rendering path is intentionally redundant. There are
// four independent layers; weakening or removing any one of them is a
// security regression. Phase 0b moved layer 1 from regex stripping to a
// SwiftSoup allowlist parser; the other three layers were untouched on
// purpose.
//
// Layer 1 — Pre-WebView sanitizer (`PresentationService.sanitizeHTML`).
//   Parses input with SwiftSoup, drops dangerous element types
//   (script, iframe, object, embed, form, input, button, base, meta, link,
//   applet, frame, frameset, noscript, style), strips on* event handlers,
//   neutralizes javascript:/vbscript:/non-image data: URLs, and removes
//   CSS expression(), behavior:, @import, and remote url() values.
//   Defends against: tag-based XSS, event-handler XSS, dangerous URL
//   schemes, base-tag hijacking, form/credential exfiltration, CSS
//   expression XSS.
//
// Layer 2 — Document Content-Security-Policy (`PresentationService
//   .injectDocumentDefaults`). Even if the sanitizer misses something,
//   the CSP on the rendered document blocks default-src, restricts
//   img-src/style-src/connect-src/frame-src by remote-resources mode,
//   and disables object-src entirely.
//   Defends against: post-sanitizer code execution, frame embedding,
//   exfiltration via fetch/XHR, plugin loading.
//
// Layer 3 — JavaScript disabled at the WKWebView level
//   (`prefs.allowsContentJavaScript = false` in `makeNSView`). Even if a
//   <script> tag survived layers 1 and 2, the WebView refuses to run it.
//   Defends against: residual script execution from any source.
//
// Layer 4 — Navigation blocking (`navigationDecision`). Only same-document
//   anchors and explicit user link clicks survive; meta-refresh, form
//   POSTs, top-level scheme jumps, and other auto-navigation are
//   cancelled. Link clicks open in the user's default browser instead
//   of replacing the companion view.
//   Defends against: meta-refresh redirect, form action navigation,
//   companion-view replacement, scheme-jump escapes.
//
// `loadHTMLString(html, baseURL: nil)` is also used deliberately — there
// is no implicit base URL the document can use to resolve relative
// references against an attacker-controlled origin.
//
// AppConfig.htmlSanitizerVersion tracks layer 1's rule generation; bump
// it when material rules change so we can correlate output with a
// known sanitizer revision.

struct RichHTMLView: NSViewRepresentable {
    @ObservedObject var state: RichHTMLState

    private let workspace: WorkspaceOpening
    private let browserActivator: BrowserActivating

    init(
        state: RichHTMLState,
        workspace: WorkspaceOpening = NSWorkspace.shared,
        browserActivator: BrowserActivating = DefaultBrowserActivator()
    ) {
        self.state = state
        self.workspace = workspace
        self.browserActivator = browserActivator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(workspace: workspace, browserActivator: browserActivator)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        load(state.html, into: webView, coordinator: context.coordinator)
        DispatchQueue.main.async {
            webView.window?.title = state.title
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != state.html {
            load(state.html, into: webView, coordinator: context.coordinator)
        }
        if webView.window?.title != state.title {
            DispatchQueue.main.async {
                webView.window?.title = state.title
            }
        }
    }

    private func load(_ html: String, into webView: WKWebView, coordinator: Coordinator) {
        coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func navigationDecision(
        url: URL?,
        navigationType: WKNavigationType,
        isMainFrame: Bool
    ) -> RichHTMLNavigationDecision {
        guard let url else { return .allow }

        let scheme = url.scheme?.lowercased()
        let isHTTPURL = scheme == "http" || scheme == "https"
        let isSafeExternalScheme = scheme == "mailto" || scheme == "tel"

        if navigationType == .linkActivated {
            return (isHTTPURL || isSafeExternalScheme) ? .openExternal : .cancel
        }

        // Keep Bob-authored HTML inside the initial document. Any
        // automatic top-level navigation (for example meta refresh or a
        // form post) gets blocked instead of replacing the companion view.
        if isMainFrame, let scheme, scheme != "about", scheme != "data" {
            return .cancel
        }

        return .allow
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        fileprivate var lastHTML = ""

        private let workspace: WorkspaceOpening
        private let browserActivator: BrowserActivating

        init(workspace: WorkspaceOpening, browserActivator: BrowserActivating) {
            self.workspace = workspace
            self.browserActivator = browserActivator
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let decision = RichHTMLView.navigationDecision(
                url: navigationAction.request.url,
                navigationType: navigationAction.navigationType,
                isMainFrame: navigationAction.targetFrame?.isMainFrame ?? false
            )

            switch decision {
            case .allow:
                decisionHandler(.allow)
            case .cancel:
                decisionHandler(.cancel)
            case .openExternal:
                if let url = navigationAction.request.url {
                    _ = ExternalURLPresenter.open(
                        url,
                        workspace: workspace,
                        browserActivator: browserActivator
                    )
                }
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                webView.window?.title = webView.title ?? webView.window?.title ?? "Bob's View"
            }
        }
    }
}
