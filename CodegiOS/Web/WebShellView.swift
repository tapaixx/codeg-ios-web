import SwiftUI

/// The app's main screen: the selected server's web client, full-bleed, under a
/// one-line native bar whose title is the server switcher.
///
/// That bar is the only native chrome. It exists because the web client has no
/// notion of "which server" — a browser tab is one origin — while this app
/// keeps several. Everything below it is the page.
struct WebShellView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(model.selectedServer?.name ?? "Codeg")
                .toolbarTitleDisplayMode(.inline)
                .toolbarTitleMenu { serverSwitcherMenu }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            model.reloadWeb()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Reload")
                    }
                }
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
                onTokenRejected: { model.tokenRejected = true }
            )
            // A new server, a new endpoint or a new token is a new page. The
            // `reloadTick` lets the toolbar button force one for the same server.
            .id("\(server.id)|\(baseURL.absoluteString)|\(token.hashValue)|\(model.reloadTick)")
            .ignoresSafeArea(edges: .bottom)
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

    @ViewBuilder
    private var serverSwitcherMenu: some View {
        Picker("Server", selection: $model.selectedServerID) {
            ForEach(model.serverStore.servers) { server in
                Text(server.name).tag(Optional(server.id))
            }
        }
        Divider()
        Button("Manage Servers…") {
            model.serversSheetPresented = true
        }
    }
}
