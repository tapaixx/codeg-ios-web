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
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )
}
