import AppKit
import Combine
import SwiftUI
import WebKit

@MainActor
final class WebViewStore: ObservableObject {
    @Published var lastError: String?
    weak var webView: WKWebView?

    func reload() {
        lastError = nil
        webView?.reload()
    }

    func openInBrowser() {
        guard let url = webView?.url else { return }
        NSWorkspace.shared.open(url)
    }
}

struct AetherWebView: NSViewRepresentable {
    let url: URL
    let token: String?
    let store: WebViewStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = true

        if let token, !token.isEmpty {
            let script = """
            try {
                sessionStorage.setItem('aether-token', \(Self.jsString(token)));
                sessionStorage.setItem('opendots-token', \(Self.jsString(token)));
            } catch (e) {}
            """
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: script,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.customUserAgent = "AETHER/0.1 (macOS)"
        webView.setValue(true, forKey: "drawsBackground")

        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        store.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        store.webView = webView
    }

    private static func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed]
        ), let string = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return string
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let store: WebViewStore

        init(store: WebViewStore) {
            self.store = store
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if navigationAction.targetFrame == nil {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""
            let host = url.host?.lowercased() ?? ""

            switch scheme {
            case "http", "https":
                if host == "127.0.0.1" || host == "localhost" || host == "::1" {
                    decisionHandler(.allow)
                } else {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                }
            case "about", "data", "blob":
                decisionHandler(.allow)
            case "file":
                decisionHandler(.allow)
            default:
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            store.lastError = nil
        }

        @available(macOS 12.0, *)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = "AETHER"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = "AETHER"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }

        private func report(_ error: Error) {
            let error = error as NSError
            if error.domain == NSURLErrorDomain,
               error.code == NSURLErrorCancelled {
                return
            }
            store.lastError = error.localizedDescription
        }
    }
}
