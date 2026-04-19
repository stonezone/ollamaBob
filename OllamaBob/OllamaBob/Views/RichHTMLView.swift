import SwiftUI
import WebKit
import AppKit

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
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                _ = workspace.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
