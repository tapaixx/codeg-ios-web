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
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable { case log = "Log", diagnostics = "Diagnostics" }

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
                        Button("Clear", systemImage: "trash", role: .destructive) {
                            console.clear()
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
