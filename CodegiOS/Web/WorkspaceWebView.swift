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
    /// Bumped when the app returns to the foreground; each change makes the
    /// page drop and rebuild its event socket (see `resumeScript`).
    var resumeTick: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.userContentController.addUserScript(Self.tokenScript(token, origin: baseURL))
        config.userContentController.addUserScript(Self.touchScript)
        config.userContentController.addUserScript(Self.resumeScript)

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
        if context.coordinator.lastResumeTick != resumeTick {
            context.coordinator.lastResumeTick = resumeTick
            webView.evaluateJavaScript("window.__codegIOS && window.__codegIOS.resume && window.__codegIOS.resume();")
        }
        guard let destination = pendingDestination else { return }
        webView.load(URLRequest(url: Self.workspaceURL(baseURL, destination: destination)))
        DispatchQueue.main.async { pendingDestination = nil }
    }

    fileprivate static func style(_ webView: WKWebView) {
        // The page is a single-page app that owns its own history; the swipe
        // gesture would only ever step backwards through `/workspace` reloads.
        webView.allowsBackForwardNavigationGestures = false
        // No 3D-touch / long-press link preview: on a phone that is one more
        // thing a long press can summon over the transcript.
        webView.allowsLinkPreview = false
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

    /// Keeps a long press from opening the page's context menus on touch.
    ///
    /// The web client wraps the conversation panel (and file references,
    /// images…) in Radix `ContextMenu` triggers. On touch and pen, Radix arms
    /// a 700ms long-press timer on `pointerdown` and disarms it on the first
    /// `pointermove`/`pointerup`/`pointercancel`. That was built for a desktop
    /// right-click stand-in; on a phone a long press to select text or just
    /// hold a finger still pops a menu over the transcript and drops the
    /// composer's focus. Three layers, because the first attempt (a synthetic
    /// `pointermove` alone) did not take on a device: the 700ms timer is never
    /// scheduled in the first place, a zero-distance `pointermove` disarms it
    /// if it was, and a `contextmenu` event never reaches the page on touch.
    /// Mouse and trackpad (iPad) keep their real context menus. WebKit's own
    /// callout on links and images is turned off alongside, and the page's
    /// floating selection toolbar is hidden on touch — see the stylesheet.
    private static let touchScript = WKUserScript(
        source: """
        (function () {
          var TRIGGER = '[data-slot="context-menu-trigger"]';
          var coarse = window.matchMedia("(hover: none) and (pointer: coarse)");
          function trigger(e) {
            return e.target && e.target.closest ? e.target.closest(TRIGGER) : null;
          }

          // 1. Radix arms its long press with `setTimeout(open, 700)` from inside
          //    its pointerdown handler. While a touch pointerdown on a trigger is
          //    being dispatched, a 700ms timer is that timer; hand back a dead id.
          var arming = false;
          var nativeSetTimeout = window.setTimeout;
          window.setTimeout = function (fn, delay) {
            if (arming && delay === 700) return 0;
            return nativeSetTimeout.apply(window, arguments);
          };
          document.addEventListener("pointerdown", function (e) {
            if (e.pointerType === "mouse" || !trigger(e)) return;
            arming = true;
            // Dispatch is synchronous; if something stops propagation before the
            // bubble listener below, this still lowers the flag.
            nativeSetTimeout.call(window, function () { arming = false; }, 0);
          }, true);

          // 2. Belt and braces: after the handlers have run, a zero-distance
          //    pointermove is what Radix disarms on.
          document.addEventListener("pointerdown", function (e) {
            if (!arming) return;
            arming = false;
            var el = trigger(e);
            if (!el) return;
            el.dispatchEvent(new PointerEvent("pointermove", {
              bubbles: true, cancelable: true,
              pointerId: e.pointerId, pointerType: e.pointerType, isPrimary: e.isPrimary,
              clientX: e.clientX, clientY: e.clientY
            }));
          }, false);

          // 3. And if WebKit reports the long press as a contextmenu event, it
          //    never reaches the page on a touch device.
          document.addEventListener("contextmenu", function (e) {
            if (coarse.matches && trigger(e)) { e.preventDefault(); e.stopImmediatePropagation(); }
          }, true);

          var style = document.createElement("style");
          style.textContent =
            "a, img { -webkit-touch-callout: none; }" +
            // The page's own floating selection toolbar (copy / quote / ask —
            // `selection-action-bubble.tsx`) is built for a mouse selection. On
            // touch it appears on top of iOS's own Copy/Look Up callout, and the
            // two fight over the selection. Touch keeps the system one.
            "@media (hover: none) and (pointer: coarse) {" +
            "  div[role=\\"toolbar\\"].absolute.rounded-full.z-30 { display: none !important; }" +
            "}";
          (document.head || document.documentElement).appendChild(style);
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    /// Makes coming back from the background cost one reconnect, not a refresh.
    ///
    /// iOS freezes the page while the app is in the background, and its event
    /// socket dies with the radio. The web client only learns that from the
    /// socket's `close` event, which WebKit delivers late (or not until TCP
    /// gives up), and it neither pings nor watches `visibilitychange`; until
    /// then it believes it is connected and everything the agent streamed in
    /// the meantime never arrives. A refresh fixes it because a fresh socket
    /// re-attaches with `since_seq` and the reconnect hooks refetch state.
    ///
    /// So the app tracks the page's `/ws/events` sockets and, on every return
    /// to the foreground, closes the one that is open. That fires `close` at
    /// once; the transport's own backoff (1s on a fresh counter), health probe
    /// and `__ready__` do the rest — the same path a genuine drop takes.
    private static let resumeScript = WKUserScript(
        source: """
        (function () {
          var Native = window.WebSocket;
          var sockets = [];
          function Tracked(url, protocols) {
            var ws = protocols === undefined ? new Native(url) : new Native(url, protocols);
            if (String(url).indexOf("/ws/events") !== -1) {
              sockets.push(ws);
              ws.addEventListener("close", function () {
                var i = sockets.indexOf(ws); if (i !== -1) sockets.splice(i, 1);
              });
            }
            return ws;
          }
          Tracked.prototype = Native.prototype;
          Tracked.CONNECTING = Native.CONNECTING; Tracked.OPEN = Native.OPEN;
          Tracked.CLOSING = Native.CLOSING; Tracked.CLOSED = Native.CLOSED;
          window.WebSocket = Tracked;
          window.__codegIOS = window.__codegIOS || {};
          window.__codegIOS.resume = function () {
            sockets.slice().forEach(function (ws) {
              if (ws.readyState === Native.OPEN || ws.readyState === Native.CONNECTING) {
                try { ws.close(4000, "app resumed"); } catch (e) {}
              }
            });
          };
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

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
        var lastResumeTick = 0
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
