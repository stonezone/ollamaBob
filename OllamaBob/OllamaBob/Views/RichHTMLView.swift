import SwiftUI
import WebKit
import AppKit

enum RichHTMLNavigationDecision: Equatable {
    case allow
    case cancel
    case openExternal
}

struct RichHTMLView: NSViewRepresentable {
    @ObservedObject var state: RichHTMLState

    private let workspace: WorkspaceOpening

    init(
        state: RichHTMLState,
        workspace: WorkspaceOpening = NSWorkspace.shared
    ) {
        self.state = state
        self.workspace = workspace
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(workspace: workspace)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        load(state.html, into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != state.html {
            load(state.html, into: webView, coordinator: context.coordinator)
        }
        if webView.window?.title != state.title {
            webView.window?.title = state.title
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

        if navigationType == .linkActivated {
            return isHTTPURL ? .openExternal : .cancel
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

        init(workspace: WorkspaceOpening) {
            self.workspace = workspace
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let decision = RichHTMLView.navigationDecision(
                url: navigationAction.request.url,
                navigationType: navigationAction.navigationType,
                isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true
            )

            switch decision {
            case .allow:
                decisionHandler(.allow)
            case .cancel:
                decisionHandler(.cancel)
            case .openExternal:
                if let url = navigationAction.request.url {
                    _ = workspace.open(url)
                }
                decisionHandler(.cancel)
            }
        }
    }
}
