import SwiftUI
import Observation

/// The shell's state: which server is selected, where the web client should go
/// next, and the app-wide activity poll that feeds the background watcher.
///
/// The screens are the web client's, so there is no navigation state here —
/// a destination is a URL for the page (`webDestination`), not a pushed view.
@MainActor
@Observable
final class AppModel {
    let serverStore: ServerStore

    /// App-wide pulse of the selected server's sessions — the safety net under
    /// `ServerEventHub` for noticing which ones are running.
    let activity = ActivityModel()

    // MARK: - Server selection

    private static let lastServerKey = "codeg.lastSelectedServerID"

    var selectedServerID: ServerProfile.ID? {
        didSet {
            guard oldValue != selectedServerID else { return }
            resetServerScopedState()
            UserDefaults.standard.set(selectedServerID?.uuidString, forKey: Self.lastServerKey)
        }
    }

    var serversSheetPresented = false
    var consolePresented = false

    init(serverStore: ServerStore? = nil) {
        let store = serverStore ?? ServerStore()
        self.serverStore = store
        // Restore the last-used server, falling back to the first: the app
        // comes up already pointed at a server.
        let persisted = UserDefaults.standard.string(forKey: Self.lastServerKey).flatMap(UUID.init)
        self.selectedServerID = store.servers.first { $0.id == persisted }?.id ?? store.servers.first?.id
    }

    var selectedServer: ServerProfile? {
        guard let id = selectedServerID else { return nil }
        return serverStore.servers.first { $0.id == id }
    }

    /// HTTP client for the selected server, if its token resolves.
    func selectedClient() -> CodegClient? {
        guard let server = selectedServer else { return nil }
        return serverStore.client(for: server)
    }

    // MARK: - Web shell

    /// Where the web client should go next — set by a Live Activity tap, a
    /// notification or a `codegweb://` link, consumed by `WorkspaceWebView` as
    /// one page load.
    var webDestination: WebDestination?
    /// The page bounced to `/login`: the server rejected the stored token.
    /// Cleared when the server, its endpoint or its token changes.
    var tokenRejected = false
    /// Bumped by the menu's Reload to force a fresh page load.
    private(set) var reloadTick = 0
    /// Bumped when the scene becomes active again; the page reconnects its
    /// event socket on each change (see `WorkspaceWebView.resumeScript`).
    private(set) var resumeTick = 0

    func reloadWeb() {
        tokenRejected = false
        reloadTick &+= 1
    }

    func webDidResume() {
        resumeTick &+= 1
    }

    /// Resolve a conversation to the web's deep-link shape. The Live Activity
    /// record and `codegweb://conversation/<id>` carry only the id; the web client
    /// also needs the folder and the agent (`DeepLinkBootstrap`), so this is one
    /// round-trip. A conversation the server no longer has lands on the
    /// workspace root, which is the web's own behavior for a stale link.
    private func routeWeb(toConversation id: Int) {
        guard let client = selectedClient(), let serverID = selectedServerID else {
            webDestination = .workspace
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let destination: WebDestination
            do {
                let summary = try await client.conversationDetail(id: id).summary
                destination = .conversation(id: id, folderID: summary.folderId, agent: summary.agentType)
            } catch {
                destination = .workspace
            }
            // The lookup was for one server; if another was selected meanwhile,
            // its ids mean nothing there.
            guard self.selectedServerID == serverID else { return }
            self.webDestination = destination
        }
    }

    // MARK: - Entry points

    /// The system-owned continued-processing Live Activity has no custom URL, so
    /// iOS launches the app with NSUserActivityTypeLiveActivity. Resolve the
    /// task from the lightweight persisted routing hints.
    func handleLiveActivityLaunch() {
        let store = BackgroundAgentNavigationStore.shared
        guard let destination = store.launchDestination() else { return }

        switch destination {
        case .activity:
            webDestination = .workspace

        case .newSession(let recordID, let serverID, _):
            guard serverStore.servers.contains(where: { $0.id == serverID }) else {
                store.invalidate(recordID)
                webDestination = .workspace
                return
            }
            if selectedServerID != serverID { selectedServerID = serverID }
            webDestination = .workspace

        case .conversation(let recordID, let serverID, let conversationID):
            guard serverStore.servers.contains(where: { $0.id == serverID }) else {
                store.invalidate(recordID)
                webDestination = .workspace
                return
            }
            if selectedServerID != serverID { selectedServerID = serverID }
            routeWeb(toConversation: conversationID)
        }
    }

    /// Handle a `codegweb://conversation/<id>[?server=<uuid>]` link (also what
    /// a notification tap turns into). Any other `codegweb://` link opens the
    /// workspace.
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "codegweb" else { return }
        // `?server=<uuid>` names the server the id belongs to — a notification
        // about one server can arrive while another is selected.
        if let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "server" })?.value,
           let serverID = UUID(uuidString: raw),
           serverID != selectedServerID,
           serverStore.servers.contains(where: { $0.id == serverID }) {
            selectedServerID = serverID
        }
        if case .conversation(let id)? = Route.from(url: url) {
            routeWeb(toConversation: id)
        } else {
            webDestination = .workspace
        }
    }

    // MARK: - Server-scoped resets

    /// Conversation ids are endpoint-local. Dropped when the selected server
    /// changes…
    private func resetServerScopedState() {
        webDestination = nil
        tokenRejected = false
        activity.reset()
    }

    /// …and when the selected server is edited in place (same UUID, new
    /// URL/token) — the old endpoint's ids may not exist on the new one.
    func selectedServerEndpointChanged() {
        resetServerScopedState()
    }
}
