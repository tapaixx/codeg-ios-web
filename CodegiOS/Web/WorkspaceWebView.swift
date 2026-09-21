import SwiftUI
import WebKit

/// The codeg web client, loaded from the selected server, inside a `WKWebView`.
///
/// This is the same page a phone browser shows for `http://host:port/workspace`;
/// the app adds nothing to it and paints nothing over it. What the app does is
/// hand the page its token before it runs (the web client reads
/// `localStorage["codeg_token"]`, exactly what its `/login` form writes), keep
/// same-origin navigation inside the view, and push outside links to Safari.
///
/// One instance per server: the website data store is the shared default, so
/// the token is keyed by origin like a browser tab's would be, and switching
/// servers is a new page load, not a new store.
struct WorkspaceWebView: UIViewRepresentable {
    let baseURL: URL
    let token: String
    /// A destination to load *instead of* `/workspace` — a Live Activity tap, a
    /// `codeg://` link. Consumed once; the web client clears the query itself
    /// after it has opened the conversation (`DeepLinkBootstrap`).
    @Binding var pendingDestination: WebDestination?
    /// Set when the page bounces to `/login`: the server rejected the token.
    let onTokenRejected: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.userContentController.addUserScript(Self.tokenScript(token))

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // The page is a single-page app that owns its own history; the swipe
        // gesture would only ever step backwards through `/workspace` reloads.
        webView.allowsBackForwardNavigationGestures = false
        // Let the page lay itself out under the status bar / home indicator: it
        // declares `viewport-fit=cover` and pads with `env(safe-area-inset-*)`.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        #if DEBUG
        webView.isInspectable = true
        #endif

        context.coordinator.webView = webView
        webView.load(URLRequest(url: Self.workspaceURL(baseURL, destination: pendingDestination)))
        DispatchQueue.main.async { pendingDestination = nil }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard let destination = pendingDestination else { return }
        webView.load(URLRequest(url: Self.workspaceURL(baseURL, destination: destination)))
        DispatchQueue.main.async { pendingDestination = nil }
    }

    // MARK: - URLs

    static func workspaceURL(_ base: URL, destination: WebDestination?) -> URL {
        var components = URLComponents(url: base.appendingPathComponent("workspace"), resolvingAgainstBaseURL: false)!
        if let destination {
            components.queryItems = destination.queryItems
        }
        return components.url!
    }

    /// Runs before any of the page's own scripts, on every document at this
    /// origin, so the very first `/workspace` load already finds a token and
    /// never detours through `/login`. The token is JSON-encoded into the script
    /// so no character in it can escape the string literal.
    private static func tokenScript(_ token: String) -> WKUserScript {
        let encoded = String(data: try! JSONEncoder().encode(token), encoding: .utf8)!
        let source = """
        try { window.localStorage.setItem("codeg_token", \(encoded)); } catch (e) {}
        window.__codegIOS = { version: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")" };
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    // MARK: - Delegate

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WorkspaceWebView
        weak var webView: WKWebView?

        init(_ parent: WorkspaceWebView) { self.parent = parent }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }

            // The app's own scheme — a `codeg://` link rendered by the page.
            if url.scheme?.lowercased() == "codeg" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            // Anything that leaves the server's origin goes to Safari. The page
            // opens external links with `window.open(_, "_blank", "noreferrer")`,
            // which lands in `createWebViewWith` below; this catches plain anchors.
            if navigationAction.navigationType == .linkActivated, !Self.sameOrigin(url, parent.baseURL) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The web client sends a rejected token here (`web-auth.ts`). The
            // app has a better place to fix that than the page's own form: the
            // server editor, which also updates the Keychain.
            if webView.url?.path.hasPrefix("/login") == true {
                parent.onTokenRejected()
            }
        }

        /// `window.open` from the page: the web client uses it only for external
        /// links (`link-open.ts`), so every popup is a Safari hand-off. Returning
        /// nil opens nothing in-app.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url, url.scheme?.hasPrefix("http") == true {
                UIApplication.shared.open(url)
            }
            return nil
        }

        private static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
            a.scheme?.lowercased() == b.scheme?.lowercased()
                && a.host?.lowercased() == b.host?.lowercased()
                && (a.port ?? defaultPort(a)) == (b.port ?? defaultPort(b))
        }

        private static func defaultPort(_ url: URL) -> Int {
            url.scheme?.lowercased() == "https" ? 443 : 80
        }
    }
}

/// Where in the web client to land. Mirrors the query `DeepLinkBootstrap`
/// reads: a conversation needs its folder and agent alongside its id.
enum WebDestination: Equatable {
    case workspace
    case conversation(id: Int, folderID: Int, agent: AgentType)

    var queryItems: [URLQueryItem]? {
        switch self {
        case .workspace:
            return nil
        case .conversation(let id, let folderID, let agent):
            return [
                URLQueryItem(name: "folderId", value: String(folderID)),
                URLQueryItem(name: "conversationId", value: String(id)),
                URLQueryItem(name: "agent", value: agent.rawValue),
            ]
        }
    }
}
