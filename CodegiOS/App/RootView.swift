import SwiftUI
import WidgetKit

/// App shell.
///
/// The screens are the web client's. This app is a native *shell* around it:
/// it remembers servers and their tokens, hosts the web client in a
/// `WKWebView` pointed at the selected server (``WebShellView``), and carries
/// the pieces a browser tab cannot — the Live Activity for an in-flight agent,
/// background continuity, and actionable notifications
/// (``BackgroundAgentCoordinator`` fed by ``RunningTurnWatcher``).
///
/// First launch with no saved servers shows the onboarding screen instead.
struct RootView: View {
    @State private var model = AppModel()
    @State private var appearance = AppearanceStore()
    @State private var watcher = RunningTurnWatcher()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.serverStore.servers.isEmpty {
                OnboardingView(store: model.serverStore) { profile in
                    model.selectedServerID = profile.id
                }
            } else {
                WebShellView(model: model)
            }
        }
        .tint(Theme.accent)
        // The native screens that remain (onboarding, server management) still
        // draw with the ported design system; the web page paints itself.
        .environment(\.webTheme, appearance.themeColor)
        .environment(appearance)
        .preferredColorScheme(appearance.mode.colorScheme)
        .onOpenURL { model.handle(url: $0) }
        .onContinueUserActivity(NSUserActivityTypeLiveActivity) { _ in
            model.isCompact = horizontalSizeClass == .compact
            model.handleLiveActivityLaunch()
        }
        .onChange(of: horizontalSizeClass, initial: true) { _, size in
            model.isCompact = size == .compact
        }
        // If the selected server is edited in place (same UUID, new endpoint),
        // its conversation ids may no longer be valid — drop them.
        // (Switching servers is handled by AppModel.selectedServerID.didSet.)
        .onChange(of: model.selectedServer?.urlString) { _, _ in
            model.selectedServerEndpointChanged()
        }
        // Closing the server editor after a token was rejected is the retry.
        .onChange(of: model.serversSheetPresented) { _, presented in
            if !presented { model.tokenRejected = false }
        }
        // Poll the selected server's running sessions so the watcher can attach
        // to them. Restarts when the scene activates or the server identity /
        // endpoint changes; pauses in the background (the attached sockets
        // themselves keep running under continued processing).
        .task(id: activityPulseID) {
            guard scenePhase == .active else { return }
            await model.activity.autoRefresh(client: model.selectedClient())
        }
        // The server's global side-channel: a session flipping to running is
        // known within a round-trip instead of at the next poll. Keyed on the
        // server only (not the scene phase) so it keeps listening while the
        // process is alive in the background under a continued-processing
        // task; a suspended socket simply reconnects on resume.
        .task(id: hubID) {
            guard let client = model.selectedClient() else { return }
            let hub = ServerEventHub(baseURL: client.baseURL, token: client.token)
            hub.start()
            defer { hub.close() }
            for await change in hub.changes {
                watcher.apply(change)
            }
        }
        .onChange(of: model.activity.running.map(\.id), initial: true) { _, _ in
            watcher.sync(
                running: model.activity.running,
                server: model.selectedServer,
                client: model.selectedClient()
            )
        }
        .sheet(isPresented: $model.serversSheetPresented) {
            ManageServersSheet(store: model.serverStore, selectedServerID: $model.selectedServerID)
        }
    }

    private var hubID: String {
        "\(model.selectedServerID?.uuidString ?? "none")|\(model.selectedServer?.urlString ?? "")"
    }

    /// Identity for the activity poller's `.task` — composes everything that
    /// should restart the loop.
    private var activityPulseID: String {
        let server = model.selectedServerID?.uuidString ?? "none"
        let endpoint = model.selectedServer?.urlString ?? ""
        return "\(String(describing: scenePhase))|\(server)|\(endpoint)"
    }
}

// MARK: - Sheets

/// Server management presented from the title menu — `ServerListView` wrapped
/// in its own stack with a Done button.
private struct ManageServersSheet: View {
    let store: ServerStore
    @Binding var selectedServerID: ServerProfile.ID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ServerListView(store: store, selectedServerID: $selectedServerID)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                            .tint(Theme.accent)
                    }
                }
        }
    }
}

/// Empty-column backdrop with a centered hint, used when nothing is selected.
struct ColumnPlaceholder: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    /// Optional call-to-action (e.g. "Manage Servers" when no server is selected).
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ZStack {
            CodegBackground()
            EmptyStateView(icon: icon, title: title, message: message, actionTitle: actionTitle, action: action)
        }
    }
}

#Preview {
    RootView().preferredColorScheme(.dark)
}
