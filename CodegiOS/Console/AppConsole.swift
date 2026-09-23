import Foundation
import Observation
import WebKit

/// The app's own console: what the page prints, what it throws, and what the
/// shell's background pieces do — kept on the device so a problem can be
/// looked at without a Mac and Safari's Web Inspector.
///
/// A ring buffer of the most recent entries, in memory only; nothing is
/// written to disk or sent anywhere.
@MainActor
@Observable
final class AppConsole {
    static let shared = AppConsole()

    enum Level: String, CaseIterable, Sendable {
        case debug, log, info, warn, error
    }

    enum Source: String, Sendable {
        /// The web client: `console.*`, uncaught errors, rejected promises.
        case page
        /// The shell: event sockets, the background watcher, page loads.
        case app
        /// A line typed into the console and its result.
        case eval
    }

    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let level: Level
        let source: Source
        let message: String
    }

    private(set) var entries: [Entry] = []

    /// One request, as the Network tab shows it. Page requests are fetch, XHR,
    /// WebSocket and resource loads observed in the page; app requests are the
    /// shell's own HTTP calls to the server.
    struct Request: Identifiable, Sendable {
        enum Kind: String, Sendable { case fetch, xhr, websocket, resource, native }
        let id: String
        var source: Source
        var kind: Kind
        var method: String
        var url: String
        var startedAt: Date
        var status: Int?
        var durationMs: Double?
        var responseSize: Int?
        var contentType: String?
        var requestBody: String?
        var responseBody: String?
        var error: String?
        /// WebSocket frame counts.
        var sent = 0
        var received = 0
        var lastFrame: String?

        var isFinished: Bool { status != nil || error != nil || durationMs != nil }
        var failed: Bool { error != nil || (status ?? 0) >= 400 }
    }

    private(set) var requests: [Request] = []
    private static let requestCapacity = 500
    private static let maxBodyLength = 20_000
    private static let capacity = 1000
    private static let maxMessageLength = 4000

    /// The main page's web view, for diagnostics and the JS runner.
    weak var webView: WKWebView?

    func append(_ message: String, level: Level = .log, source: Source = .app) {
        let text = message.count > Self.maxMessageLength
            ? String(message.prefix(Self.maxMessageLength)) + "…"
            : message
        entries.append(Entry(date: Date(), level: level, source: source, message: text))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    func clear() { entries.removeAll() }
    func clearRequests() { requests.removeAll() }

    func upsertRequest(id: String, _ update: (inout Request) -> Void, create: () -> Request) {
        if let index = requests.lastIndex(where: { $0.id == id }) {
            update(&requests[index])
        } else {
            var request = create()
            update(&request)
            requests.append(request)
            if requests.count > Self.requestCapacity {
                requests.removeFirst(requests.count - Self.requestCapacity)
            }
        }
    }

    static func clip(_ text: String?) -> String? {
        guard let text else { return nil }
        return text.count > maxBodyLength ? String(text.prefix(maxBodyLength)) + "\n… (truncated)" : text
    }

    /// Record one of the shell's own HTTP calls (from any thread).
    nonisolated static func recordNative(
        url: URL, requestBody: Data?, status: Int?, responseBody: Data?,
        durationMs: Double, error: String?
    ) {
        let id = UUID().uuidString
        let body = requestBody.flatMap { String(data: $0, encoding: .utf8) }
        let response = responseBody.flatMap { String(data: $0, encoding: .utf8) }
        let size = responseBody?.count
        Task { @MainActor in
            shared.upsertRequest(id: id, { r in
                r.status = status
                r.durationMs = durationMs
                r.responseSize = size
                r.requestBody = clip(body)
                r.responseBody = clip(response)
                r.error = error
                r.contentType = "application/json"
            }, create: {
                Request(id: id, source: .app, kind: .native, method: "POST",
                        url: url.absoluteString, startedAt: Date().addingTimeInterval(-durationMs / 1000))
            })
        }
    }

    /// Apply one network post from the page script.
    func recordPage(_ body: [String: Any]) {
        guard let id = body["id"] as? String else { return }
        let phase = body["phase"] as? String ?? ""
        let kind = (body["type"] as? String).flatMap(Request.Kind.init(rawValue:)) ?? .fetch
        func int(_ key: String) -> Int? { (body[key] as? NSNumber)?.intValue }
        func double(_ key: String) -> Double? { (body[key] as? NSNumber)?.doubleValue }
        func string(_ key: String) -> String? { body[key] as? String }
        upsertRequest(id: id, { r in
            switch phase {
            case "start":
                r.requestBody = Self.clip(string("body"))
            case "end":
                r.status = int("status")
                r.durationMs = double("duration")
                r.responseSize = int("size")
                r.contentType = string("contentType")
                r.responseBody = Self.clip(string("body"))
            case "error":
                r.error = string("error") ?? "failed"
                r.durationMs = double("duration")
            case "ws-open":
                r.status = 101
            case "ws-send":
                r.sent += 1; r.lastFrame = Self.clip(string("body"))
            case "ws-message":
                r.received += 1; r.lastFrame = Self.clip(string("body"))
            case "ws-close":
                r.durationMs = double("duration")
                if let code = int("code"), code != 1000 { r.error = "closed \(code) \(string("reason") ?? "")" }
            case "resource":
                r.status = int("status") ?? 200
                r.durationMs = double("duration")
                r.responseSize = int("size")
            default: break
            }
        }, create: {
            Request(id: id, source: .page, kind: kind, method: string("method") ?? "GET",
                    url: string("url") ?? "", startedAt: Date())
        })
    }

    /// Log from any thread.
    nonisolated static func log(_ message: String, level: Level = .log) {
        Task { @MainActor in shared.append(message, level: level, source: .app) }
    }

    /// Everything as plain text, for the clipboard.
    func transcript() -> String {
        let format = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return entries.map {
            "\($0.date.formatted(format)) [\($0.source.rawValue)/\($0.level.rawValue)] \($0.message)"
        }.joined(separator: "\n")
    }

    // MARK: - Page bridge

    /// Handler name the page script posts to.
    static let messageHandlerName = "codegConsole"

    /// Receives the page's posts. Held through a weak box so the content
    /// controller, which retains its handlers, doesn't keep this alive.
    final class Bridge: NSObject, WKScriptMessageHandler {
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any] else { return }
            let level = (body["level"] as? String).flatMap(Level.init(rawValue:)) ?? .log
            let text = body["message"] as? String ?? ""
            let webView = message.webView
            Task { @MainActor in
                if body["kind"] as? String == "net" {
                    AppConsole.shared.recordPage(body)
                    return
                }
                if body["kind"] as? String == "focus" {
                    // WebKit's focus zoom lands just after focus; read the
                    // native scale now and a beat later.
                    let before = webView?.scrollView.zoomScale ?? 1
                    AppConsole.shared.append("\(text) · zoomScale \(Self.format(before))", level: .info, source: .page)
                    try? await Task.sleep(for: .milliseconds(600))
                    let after = webView?.scrollView.zoomScale ?? 1
                    AppConsole.shared.append("  +600ms zoomScale \(Self.format(after))", level: after > 1.001 ? .warn : .info, source: .page)
                } else {
                    AppConsole.shared.append(text, level: level, source: .page)
                }
            }
        }

        private static func format(_ scale: CGFloat) -> String {
            String(format: "%.3f", Double(scale))
        }
    }

    /// Installed at document start, main frame only. Forwards console output
    /// and uncaught errors, and on each focus of an editable field reports
    /// what WebKit's focus-zoom decision depends on.
    static let pageScript = WKUserScript(
        source: """
        (function () {
          var handler = window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.codegConsole;
          if (!handler) return;
          function text(v) {
            if (typeof v === "string") return v;
            if (v instanceof Error) return (v.stack || (v.name + ": " + v.message));
            try { return JSON.stringify(v); } catch (e) { return String(v); }
          }
          function post(kind, level, parts) {
            try {
              handler.postMessage({ kind: kind, level: level,
                message: Array.prototype.map.call(parts, text).join(" ") });
            } catch (e) {}
          }
          ["debug", "log", "info", "warn", "error"].forEach(function (level) {
            var original = console[level];
            console[level] = function () {
              post("console", level, arguments);
              return original.apply(console, arguments);
            };
          });
          window.addEventListener("error", function (e) {
            post("error", "error", [e.error || (e.message + " @ " + e.filename + ":" + e.lineno)]);
          });
          window.addEventListener("unhandledrejection", function (e) {
            post("error", "error", ["Unhandled rejection:", e.reason]);
          });
          document.addEventListener("focusin", function (e) {
            var el = e.target;
            if (!el || !(el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName))) return;
            var vv = window.visualViewport;
            var meta = document.querySelector('meta[name="viewport"]');
            post("focus", "info", [
              "focus " + el.tagName.toLowerCase() + (el.isContentEditable ? "[contenteditable]" : ""),
              "· font " + getComputedStyle(el).fontSize,
              "· root " + getComputedStyle(document.documentElement).fontSize,
              "· vv.scale " + (vv ? vv.scale.toFixed(3) : "n/a"),
              "· viewport \\"" + (meta ? meta.content : "none") + "\\""
            ]);
          }, true);

          // ---- Network ----
          var seq = 0;
          function nid() { seq += 1; return "p" + Date.now().toString(36) + "-" + seq; }
          function net(o) { o.kind = "net"; try { handler.postMessage(o); } catch (e) {} }
          function abs(u) { try { return new URL(u, location.href).href; } catch (e) { return String(u); } }
          function bodyText(b) {
            if (b == null) return null;
            if (typeof b === "string") return b;
            if (b instanceof URLSearchParams) return b.toString();
            if (typeof FormData !== "undefined" && b instanceof FormData) return "[FormData]";
            if (b instanceof Blob) return "[Blob " + b.size + " bytes]";
            if (b instanceof ArrayBuffer || ArrayBuffer.isView(b)) return "[binary " + (b.byteLength || 0) + " bytes]";
            return String(b);
          }
          // Text bodies only, and not huge ones; binary is summarized.
          function readable(type) { return /json|text|javascript|xml|x-www-form/.test(type || ""); }

          var origFetch = window.fetch;
          if (origFetch) {
            window.fetch = function (input, init) {
              var id = nid(), t0 = performance.now();
              var url = abs(typeof input === "string" ? input : (input && input.url) || input);
              var method = ((init && init.method) || (input && input.method) || "GET").toUpperCase();
              net({ phase: "start", id: id, type: "fetch", method: method, url: url, body: bodyText(init && init.body) });
              return origFetch.apply(this, arguments).then(function (res) {
                var type = res.headers.get("content-type") || "";
                var len = parseInt(res.headers.get("content-length") || "", 10);
                var done = function (text, size) {
                  net({ phase: "end", id: id, status: res.status, duration: performance.now() - t0,
                        contentType: type, size: size, body: text });
                };
                if (readable(type) && !(len > 262144)) {
                  res.clone().text().then(function (text) { done(text, text.length); }, function () { done(null, isNaN(len) ? null : len); });
                } else {
                  done(type ? "[" + type + "]" : null, isNaN(len) ? null : len);
                }
                return res;
              }, function (err) {
                net({ phase: "error", id: id, duration: performance.now() - t0, error: String(err && err.message || err) });
                throw err;
              });
            };
          }

          var XHR = window.XMLHttpRequest;
          if (XHR) {
            var open = XHR.prototype.open, send = XHR.prototype.send;
            XHR.prototype.open = function (method, url) {
              this.__codeg = { id: nid(), method: String(method || "GET").toUpperCase(), url: abs(url) };
              return open.apply(this, arguments);
            };
            XHR.prototype.send = function (body) {
              var info = this.__codeg, xhr = this;
              if (info) {
                var t0 = performance.now();
                net({ phase: "start", id: info.id, type: "xhr", method: info.method, url: info.url, body: bodyText(body) });
                xhr.addEventListener("loadend", function () {
                  if (xhr.status === 0) {
                    net({ phase: "error", id: info.id, duration: performance.now() - t0, error: "network error" });
                    return;
                  }
                  var type = xhr.getResponseHeader("content-type") || "";
                  var text = null;
                  try { if ((xhr.responseType === "" || xhr.responseType === "text") && readable(type)) text = xhr.responseText; } catch (e) {}
                  net({ phase: "end", id: info.id, status: xhr.status, duration: performance.now() - t0,
                        contentType: type, size: text ? text.length : null, body: text });
                });
              }
              return send.apply(this, arguments);
            };
          }

          var WS = window.WebSocket;
          if (WS) {
            var Wrapped = function (url, protocols) {
              var ws = protocols === undefined ? new WS(url) : new WS(url, protocols);
              var id = nid(), t0 = performance.now();
              net({ phase: "start", id: id, type: "websocket", method: "WS", url: abs(url) });
              ws.addEventListener("open", function () { net({ phase: "ws-open", id: id }); });
              ws.addEventListener("message", function (e) {
                net({ phase: "ws-message", id: id, body: typeof e.data === "string" ? e.data.slice(0, 2000) : "[binary]" });
              });
              ws.addEventListener("close", function (e) {
                net({ phase: "ws-close", id: id, code: e.code, reason: e.reason, duration: performance.now() - t0 });
              });
              var s = ws.send;
              ws.send = function (data) {
                net({ phase: "ws-send", id: id, body: typeof data === "string" ? data.slice(0, 2000) : "[binary]" });
                return s.apply(ws, arguments);
              };
              return ws;
            };
            Wrapped.prototype = WS.prototype;
            Wrapped.CONNECTING = WS.CONNECTING; Wrapped.OPEN = WS.OPEN;
            Wrapped.CLOSING = WS.CLOSING; Wrapped.CLOSED = WS.CLOSED;
            window.WebSocket = Wrapped;
          }

          // Scripts, styles, images, fonts: what fetch/XHR don't see.
          try {
            new PerformanceObserver(function (list) {
              list.getEntries().forEach(function (e) {
                if (e.initiatorType === "fetch" || e.initiatorType === "xmlhttprequest") return;
                var id = nid();
                net({ phase: "start", id: id, type: "resource", method: (e.initiatorType || "GET").toUpperCase(), url: e.name });
                net({ phase: "resource", id: id, status: e.responseStatus || 200, duration: e.duration,
                      size: e.transferSize || e.encodedBodySize || null });
              });
            }).observe({ type: "resource", buffered: true });
          } catch (e) {}
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )
}
