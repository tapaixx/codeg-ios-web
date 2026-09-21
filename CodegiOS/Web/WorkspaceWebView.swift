import SwiftUI
import WebKit

/// The codeg web client, loaded from the selected server, inside a `WKWebView`.
///
/// This is the same page a phone browser shows for `http://host:port/workspace`;
/// the app adds nothing to it and paints nothing over it. What the app does is
/// hand the page its token before it runs (the web client reads
/// `localStorage["codeg_token"]`, exactly what its `/login` form writes), keep
/// the server's origin inside the view, push outside links to Safari, and give
/// the page's own popup windows (commit, push, merge, settings…) a sheet to
/// live in.
///
/// One instance per server: the website data store is the shared default, so
/// the token is keyed by origin like a browser tab's would be, and switching
/// servers is a new page load, not a new store.
struct WorkspaceWebView: UIViewRepresentable {
    let baseURL: URL
    let token: String
    /// A destination to load *instead of* `/workspace` — a Live Activity tap, a
    /// `codegweb://` link. Consumed once; the web client clears the query itself
    /// after it has opened the conversation (`DeepLinkBootstrap`).
    @Binding var pendingDestination: WebDestination?
    /// Set when the page bounces to `/login`: the server rejected the token.
    let onTokenRejected: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.userContentController.addUserScript(Self.tokenScript(token, origin: baseURL))

        let webView = WKWebView(frame: .zero, configuration: config)
        Self.style(webView)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

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

    fileprivate static func style(_ webView: WKWebView) {
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
    }

    // MARK: - URLs

    static func workspaceURL(_ base: URL, destination: WebDestination?) -> URL {
        var components = URLComponents(url: base.appendingPathComponent("workspace"), resolvingAgainstBaseURL: false)!
        if let destination {
            components.queryItems = destination.queryItems
        }
        return components.url!
    }

    /// Runs before any of the page's own scripts, so the very first `/workspace`
    /// load already finds a token and never detours through `/login`.
    ///
    /// Main frame only, and only when the document's origin is the server's:
    /// the web client embeds cross-origin frames (its browser bridge), and a
    /// script that ran there would hand the bearer token to a foreign origin.
    /// The token and the origin are JSON-encoded into the script so no
    /// character in either can escape its string literal.
    private static func tokenScript(_ token: String, origin: URL) -> WKUserScript {
        let json = JSONEncoder()
        let encodedToken = String(data: try! json.encode(token), encoding: .utf8)!
        let encodedOrigin = String(data: try! json.encode(Self.origin(of: origin)), encoding: .utf8)!
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let source = """
        if (window.location.origin === \(encodedOrigin)) {
          try { window.localStorage.setItem("codeg_token", \(encodedToken)); } catch (e) {}
          window.__codegIOS = { version: "\(version)" };
        }
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// `scheme://host[:port]` the way `window.location.origin` spells it — no
    /// port when it is the scheme's default.
    fileprivate static func origin(of url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? "http"
        let host = url.host?.lowercased() ?? ""
        if let port = url.port, port != defaultPort(scheme) {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    fileprivate static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        origin(of: a) == origin(of: b)
    }

    private static func defaultPort(_ scheme: String) -> Int {
        scheme == "https" ? 443 : 80
    }

    // MARK: - Delegate

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WorkspaceWebView
        weak var webView: WKWebView?
        /// The page's popup windows, newest last. Retained so WebKit can keep
        /// treating them as the named windows the page opened.
        private var popups: [PopupController] = []

        init(_ parent: WorkspaceWebView) { self.parent = parent }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(Self.policy(for: navigationAction, origin: parent.baseURL))
        }

        /// The main frame never leaves the server's origin — whatever kind of
        /// navigation asks (a tapped link, a script, a form): it goes to Safari
        /// instead. Sub-frames are the page's business. `codegweb://` links go to
        /// the app itself.
        fileprivate static func policy(for action: WKNavigationAction, origin: URL) -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .allow }
            if url.scheme?.lowercased() == "codegweb" {
                UIApplication.shared.open(url)
                return .cancel
            }
            guard action.targetFrame?.isMainFrame ?? true else { return .allow }
            if url.scheme?.hasPrefix("http") == true, !sameOrigin(url, origin) {
                UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The web client sends a rejected token here (`web-auth.ts`). The
            // app has a better place to fix that than the page's own form: the
            // server editor, which also updates the Keychain.
            if webView.url?.path.hasPrefix("/login") == true {
                parent.onTokenRejected()
            }
        }

        /// `window.open` from the page. Two callers, told apart by the request:
        ///
        /// - An external link (`link-open.ts`) opens a real `http(s)` URL on
        ///   another origin — that goes to Safari and gets no window.
        /// - An app window (`openAppWindow` in `api.ts`: commit, push, merge,
        ///   settings, import…) reserves a *named, empty* window inside the
        ///   click and navigates it to a same-origin path once the backend has
        ///   answered. A `null` here is what the page reports as "popup
        ///   blocked", so it gets a real web view — presented as a sheet, on
        ///   the configuration WebKit hands us so the two stay one window group.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url,
               url.scheme?.hasPrefix("http") == true,
               !WorkspaceWebView.sameOrigin(url, parent.baseURL) {
                UIApplication.shared.open(url)
                return nil
            }

            let popup = PopupController(configuration: configuration, origin: parent.baseURL)
            popup.onClose = { [weak self, weak popup] in
                self?.popups.removeAll { $0 === popup }
            }
            popups.append(popup)

            var presenter = webView.window?.rootViewController
            while let next = presenter?.presentedViewController { presenter = next }
            presenter?.present(popup, animated: true)
            return popup.webView
        }
    }
}

/// One of the page's popup windows, as a sheet. Closes when the page calls
/// `window.close()` (`webViewDidClose`) or the user drags it down.
final class PopupController: UIViewController, WKUIDelegate, WKNavigationDelegate {
    let webView: WKWebView
    private let origin: URL
    var onClose: (() -> Void)?

    init(configuration: WKWebViewConfiguration, origin: URL) {
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.origin = origin
        super.init(nibName: nil, bundle: nil)
        WorkspaceWebView.style(webView)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed { onClose?() }
    }

    func webViewDidClose(_ webView: WKWebView) {
        dismiss(animated: true)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(WorkspaceWebView.Coordinator.policy(for: navigationAction, origin: origin))
    }

    /// A popup opening a popup: only external links do that, and those go to
    /// Safari.
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
