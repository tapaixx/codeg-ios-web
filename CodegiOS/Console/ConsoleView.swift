import SwiftUI
import UIKit
import WebKit

/// The app console, as a sheet: a log of the page and the shell, a
/// diagnostics snapshot, and a line of JavaScript to run in the page.
struct ConsoleView: View {
    @Bindable var model: AppModel
    @State private var console = AppConsole.shared
    @State private var tab: Tab = .log
    @State private var filter: Filter = .all
    @State private var expression = ""
    @State private var diagnostics: [(String, String)] = []
    @State private var netQuery = ""
    @State private var netScope: NetScope = .all

    enum NetScope: String, CaseIterable {
        case all = "All", page = "Page", app = "App", failed = "Failed", sockets = "WS"
        func matches(_ r: AppConsole.Request) -> Bool {
            switch self {
            case .all: true
            case .page: r.source == .page
            case .app: r.source == .app
            case .failed: r.failed
            case .sockets: r.kind == .websocket
            }
        }
    }
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable { case log = "Log", network = "Network", diagnostics = "Diagnostics" }

    enum Filter: String, CaseIterable {
        case all = "All", problems = "Warnings & Errors", page = "Page", app = "App"

        func matches(_ entry: AppConsole.Entry) -> Bool {
            switch self {
            case .all: true
            case .problems: entry.level == .warn || entry.level == .error
            case .page: entry.source == .page
            case .app: entry.source == .app || entry.source == .eval
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch tab {
                case .log: logView
                case .network: networkView
                case .diagnostics: diagnosticsView
                }
            }
            .navigationTitle("Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Show", selection: $filter) {
                            ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        Divider()
                        Button("Copy All", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = console.transcript()
                        }
                        Button("Clear Log", systemImage: "trash", role: .destructive) {
                            console.clear()
                        }
                        Button("Clear Network", systemImage: "trash", role: .destructive) {
                            console.clearRequests()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter and actions")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Log

    private var visibleEntries: [AppConsole.Entry] {
        console.entries.filter(filter.matches)
    }

    private var logView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(visibleEntries) { entry in
                    EntryRow(entry: entry)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .id(entry.id)
                }
                .listStyle(.plain)
                .overlay {
                    if visibleEntries.isEmpty {
                        ContentUnavailableView("Nothing logged yet", systemImage: "text.alignleft")
                    }
                }
                .onChange(of: console.entries.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
                .onAppear {
                    if let id = visibleEntries.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            Divider()
            HStack(spacing: 8) {
                TextField("JavaScript", text: $expression)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(run)
                Button("Run", action: run)
                    .disabled(expression.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private func run() {
        let source = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        console.append("› \(source)", level: .log, source: .eval)
        guard let webView = console.webView else {
            console.append("No page loaded.", level: .error, source: .eval)
            return
        }
        webView.evaluateJavaScript(source) { result, error in
            Task { @MainActor in
                if let error {
                    AppConsole.shared.append(error.localizedDescription, level: .error, source: .eval)
                } else {
                    AppConsole.shared.append(Self.describe(result), level: .log, source: .eval)
                }
            }
        }
        expression = ""
    }

    private static func describe(_ value: Any?) -> String {
        guard let value else { return "undefined" }
        if let string = value as? String { return string }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }

    // MARK: - Network

    private var visibleRequests: [AppConsole.Request] {
        let q = netQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return console.requests.reversed().filter {
            netScope.matches($0) && (q.isEmpty || $0.url.lowercased().contains(q) || $0.method.lowercased() == q)
        }
    }

    private var networkView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Filter URL", text: $netQuery)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Scope", selection: $netScope) {
                    ForEach(NetScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
            List(visibleRequests) { request in
                NavigationLink {
                    RequestDetailView(requestID: request.id)
                } label: {
                    RequestRow(request: request)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            .listStyle(.plain)
            .overlay {
                if visibleRequests.isEmpty {
                    ContentUnavailableView("No requests", systemImage: "network",
                                           description: Text("Requests made after the page loaded appear here, newest first."))
                }
            }
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsView: some View {
        List {
            Section {
                ForEach(diagnostics, id: \.0) { key, value in
                    LabeledContent(key) {
                        Text(value)
                            .font(.system(.footnote, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            } footer: {
                Text("Read from the app and the page at the moment you tap Refresh.")
            }
            Section {
                Button("Refresh", systemImage: "arrow.clockwise") { refreshDiagnostics() }
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = diagnostics.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
                }
            }
        }
        .onAppear(perform: refreshDiagnostics)
    }

    private func refreshDiagnostics() {
        let info = Bundle.main.infoDictionary
        var rows: [(String, String)] = [
            ("App", "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"),
            ("iOS", UIDevice.current.systemVersion),
            ("Device", UIDevice.current.model),
            ("Server", model.selectedServer?.displayHost ?? "none"),
        ]
        guard let webView = console.webView else {
            rows.append(("Page", "not loaded"))
            diagnostics = rows
            return
        }
        rows.append(("Page URL", webView.url?.absoluteString ?? "none"))
        rows.append(("zoomScale", String(format: "%.3f", Double(webView.scrollView.zoomScale))))
        rows.append(("Web view size", "\(Int(webView.bounds.width))×\(Int(webView.bounds.height))"))
        diagnostics = rows

        let script = """
        (function () {
          var vv = window.visualViewport, meta = document.querySelector('meta[name="viewport"]');
          var el = document.activeElement;
          return {
            "innerWidth": String(window.innerWidth),
            "visualViewport.scale": vv ? vv.scale.toFixed(3) : "n/a",
            "Root font size": getComputedStyle(document.documentElement).fontSize,
            "Viewport meta": meta ? meta.content : "none",
            "Focused element": el ? el.tagName.toLowerCase() + " " + getComputedStyle(el).fontSize : "none",
            "Page zoom setting": localStorage.getItem("codeg-zoom-level") || "default",
            "User agent": navigator.userAgent
          };
        })()
        """
        webView.evaluateJavaScript(script) { result, _ in
            guard let dict = result as? [String: String] else { return }
            Task { @MainActor in
                diagnostics.append(contentsOf: dict.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
            }
        }
    }
}

private struct EntryRow: View {
    let entry: AppConsole.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.date, format: .dateTime.hour().minute().second())
                Text(entry.source.rawValue)
                if entry.level != .log { Text(entry.level.rawValue.uppercased()) }
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var color: Color {
        switch entry.level {
        case .error: .red
        case .warn: .orange
        case .debug: .secondary
        default: .primary
        }
    }
}

// MARK: - Network rows

private func formatBytes(_ n: Int?) -> String {
    guard let n else { return "–" }
    if n < 1024 { return "\(n) B" }
    if n < 1024 * 1024 { return String(format: "%.1f KB", Double(n) / 1024) }
    return String(format: "%.1f MB", Double(n) / 1024 / 1024)
}

private func formatDuration(_ ms: Double?) -> String {
    guard let ms else { return "…" }
    return ms < 1000 ? "\(Int(ms)) ms" : String(format: "%.2f s", ms / 1000)
}

private func statusText(_ r: AppConsole.Request) -> String {
    if r.kind == .websocket {
        return r.error ?? (r.durationMs != nil ? "closed" : (r.status == 101 ? "open" : "…"))
    }
    if let error = r.error { return error }
    return r.status.map(String.init) ?? "…"
}

private func statusColor(_ r: AppConsole.Request) -> Color {
    if r.failed { return .red }
    if !r.isFinished { return .secondary }
    return .green
}

private struct RequestRow: View {
    let request: AppConsole.Request

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(request.method)
                    .fontWeight(.semibold)
                Text(statusText(request))
                    .foregroundStyle(statusColor(request))
                Spacer(minLength: 4)
                Text(request.kind == .websocket
                     ? "↑\(request.sent) ↓\(request.received)"
                     : formatDuration(request.durationMs))
                    .foregroundStyle(.secondary)
            }
            .font(.system(.caption, design: .monospaced))
            Text(Self.shortURL(request.url))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
            Text("\(request.source.rawValue) · \(request.kind.rawValue) · \(formatBytes(request.responseSize))")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    /// Path and query; the origin is the same for nearly everything.
    static func shortURL(_ url: String) -> String {
        guard let u = URL(string: url), let host = u.host else { return url }
        var s = u.path.isEmpty ? "/" : u.path
        if let q = u.query { s += "?" + q }
        return u.scheme?.hasPrefix("http") == true || u.scheme?.hasPrefix("ws") == true
            ? (host == AppConsole.shared.webView?.url?.host ? s : "\(host)\(s)")
            : url
    }
}

private struct RequestDetailView: View {
    let requestID: String
    @State private var console = AppConsole.shared

    private var request: AppConsole.Request? {
        console.requests.last { $0.id == requestID }
    }

    var body: some View {
        List {
            if let r = request {
                Section("General") {
                    row("URL", r.url)
                    row("Method", r.method)
                    row("Status", statusText(r))
                    row("Kind", "\(r.source.rawValue) · \(r.kind.rawValue)")
                    row("Started", r.startedAt.formatted(date: .omitted, time: .standard))
                    row("Duration", formatDuration(r.durationMs))
                    row("Size", formatBytes(r.responseSize))
                    if let type = r.contentType { row("Content-Type", type) }
                    if r.kind == .websocket { row("Frames", "sent \(r.sent) · received \(r.received)") }
                }
                if let body = r.requestBody, !body.isEmpty {
                    Section("Request body") { bodyView(body) }
                }
                if let body = r.responseBody, !body.isEmpty {
                    Section("Response") { bodyView(body) }
                }
                if let frame = r.lastFrame {
                    Section("Last frame") { bodyView(frame) }
                }
                Section {
                    Button("Copy URL", systemImage: "link") { UIPasteboard.general.string = r.url }
                    if let body = r.responseBody {
                        Button("Copy Response", systemImage: "doc.on.doc") { UIPasteboard.general.string = body }
                    }
                }
            } else {
                Text("This request is no longer in the buffer.")
            }
        }
        .navigationTitle(request.map { RequestRow.shortURL($0.url) } ?? "Request")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ key: String, _ value: String) -> some View {
        LabeledContent(key) {
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func bodyView(_ text: String) -> some View {
        Text(Self.pretty(text))
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pretty-print JSON; anything else as-is.
    static func pretty(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let out = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: out, encoding: .utf8) else { return text }
        return s
    }
}

