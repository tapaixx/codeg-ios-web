import SwiftUI

/// The app's main screen: the selected server's web client, full-bleed.
///
/// The only native chrome is a small server pill laid over the *middle* of the
/// web client's own mobile title bar — the one region of that bar the page
/// leaves empty (its left and right clusters are three buttons each; the
/// middle is a window-drag filler). The pill is the server switcher and holds
/// the reload action. It exists because the web client has no notion of "which
/// server" — a browser tab is one origin — while this app keeps several.
struct WebShellView: View {
    @Bindable var model: AppModel

    /// The web title bar is `h-10`; the pill sits centered in it.
    private static let titleBarHeight: CGFloat = 40
    private static let pillHeight: CGFloat = 28

    var body: some View {
        ZStack(alignment: .top) {
            content
                .ignoresSafeArea()
            if model.selectedServer != nil {
                serverPill
                    .padding(.top, (Self.titleBarHeight - Self.pillHeight) / 2)
            }
        }
        .sheet(isPresented: $model.consolePresented) {
            ConsoleView(model: model)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let server = model.selectedServer, let baseURL = server.baseURL,
           let token = model.serverStore.token(for: server), !token.isEmpty,
           !model.tokenRejected {
            WorkspaceWebView(
                baseURL: baseURL,
                token: token,
                pendingDestination: $model.webDestination,
                onTokenRejected: { model.tokenRejected = true },
                resumeTick: model.resumeTick
            )
            // A new server, a new endpoint or a new token is a new page. The
            // `reloadTick` lets the menu's Reload force one for the same server.
            .id("\(server.id)|\(baseURL.absoluteString)|\(token.hashValue)|\(model.reloadTick)")
        } else if model.selectedServer != nil {
            ColumnPlaceholder(
                icon: "key.slash",
                title: model.tokenRejected ? "Token Rejected" : "Server Unavailable",
                message: model.tokenRejected
                    ? "The server did not accept this token. Edit the server to enter a new one."
                    : "This server's token is missing. Edit the server to re-enter it.",
                actionTitle: "Manage Servers",
                action: { model.serversSheetPresented = true }
            )
        } else {
            ColumnPlaceholder(
                icon: "bubble.left.and.bubble.right",
                title: "No Server Selected",
                message: "Choose a server, or add a new one.",
                actionTitle: "Manage Servers",
                action: { model.serversSheetPresented = true }
            )
        }
    }

    /// Server name + chevron, drawn like the web bar's own text (13pt medium,
    /// muted) on nothing, so it reads as part of the page. Width is capped to
    /// stay clear of the page's button clusters on the narrowest phones.
    private var serverPill: some View {
        Menu {
            Picker("Server", selection: $model.selectedServerID) {
                ForEach(model.serverStore.servers) { server in
                    Text(server.name).tag(Optional(server.id))
                }
            }
            Divider()
            Button("Reload", systemImage: "arrow.clockwise") { model.reloadWeb() }
            Button("Console", systemImage: "terminal") { model.consolePresented = true }
            Button("Manage Servers…") { model.serversSheetPresented = true }
        } label: {
            HStack(spacing: 4) {
                Text(model.selectedServer?.name ?? "Codeg")
                    .font(WebTheme.sans(13, .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: Self.pillHeight)
            .frame(maxWidth: 150)
            .contentShape(Capsule())
        }
        .accessibilityLabel("Server")
    }
}
