import Foundation
import Observation

/// Keeps the system-facing pieces of an agent turn alive now that the screens
/// are the web client's.
///
/// The web page runs its own WebSocket, but nothing in it can start a
/// continued-processing task, post a notification, or update the Dynamic
/// Island. Those hang off ``EventStream`` + ``BackgroundAgentCoordinator``,
/// which only need an ACP connection id to attach to. So for every session the
/// server reports as running, this opens a native attach of its own — a
/// read-only listener alongside the page's — and lets the existing machinery do
/// what it always did: begin a turn on attach, narrate phases, surface
/// permission / question / plan requests as actionable notifications while the
/// app is backgrounded, and end the turn when the reply completes.
///
/// It is deliberately blind to what the page is showing. A running session
/// started from the desktop gets the same treatment as one started here, which
/// is what a phone wants: it is the device in your pocket while the agent works.
@MainActor
@Observable
final class RunningTurnWatcher {
    private struct Watch {
        let task: Task<Void, Never>
        let navigationHandle: UUID
        /// The attach ended (turn complete, detached). Kept until the poll no
        /// longer lists the session, so a stale "in progress" status doesn't
        /// re-attach to a finished turn every 25 seconds.
        var finished = false
    }

    private var watches: [Int: Watch] = [:]
    private var serverID: UUID?

    /// Never more live sockets than this; the rest wait for a slot.
    private static let maxConcurrent = 4

    /// Reconcile against the latest poll. Called whenever the running set or the
    /// selected server changes.
    func sync(running: [ConversationSummary], server: ServerProfile?, client: CodegClient?) {
        if server?.id != serverID {
            cancelAll()
            serverID = server?.id
        }
        guard let server, let client else {
            cancelAll()
            return
        }

        let live = Set(running.map(\.id))
        for id in watches.keys where !live.contains(id) {
            stop(id)
        }
        for conversation in running where watches[conversation.id] == nil {
            guard watches.count < Self.maxConcurrent else { break }
            start(conversation, server: server, client: client)
        }
    }

    private func start(_ conversation: ConversationSummary, server: ServerProfile, client: CodegClient) {
        let store = BackgroundAgentNavigationStore.shared
        let handle = store.beginTask(serverID: server.id, conversationID: conversation.id, newSession: nil)
        BackgroundAgentCoordinator.shared.navigationMetadataChanged()

        let id = conversation.id
        let task = Task { [weak self] in
            await Self.attach(conversation, client: client)
            guard let self, !Task.isCancelled else { return }
            self.markFinished(id)
        }
        watches[id] = Watch(task: task, navigationHandle: handle)
    }

    private func markFinished(_ id: Int) {
        guard var watch = watches[id], !watch.finished else { return }
        watch.finished = true
        watches[id] = watch
        BackgroundAgentNavigationStore.shared.finishTask(watch.navigationHandle)
        BackgroundAgentCoordinator.shared.navigationMetadataChanged()
    }

    private func stop(_ id: Int) {
        guard let watch = watches.removeValue(forKey: id) else { return }
        watch.task.cancel()
        if !watch.finished {
            BackgroundAgentNavigationStore.shared.finishTask(watch.navigationHandle)
            BackgroundAgentCoordinator.shared.navigationMetadataChanged()
        }
    }

    private func cancelAll() {
        for id in Array(watches.keys) { stop(id) }
    }

    /// One attach, start to finish. Returns when the turn completes, the server
    /// detaches us, the socket gives up, or the task is cancelled — the stream
    /// closes on every exit, which is what ends the continued-processing turn.
    private static func attach(_ conversation: ConversationSummary, client: CodegClient) async {
        // No live connection means the status is stale or the agent has already
        // gone; there is nothing to listen to.
        guard let found = try? await client.findConnection(
            conversationId: conversation.id,
            sessionId: conversation.externalId,
            agentType: conversation.agentType
        ) else { return }

        let stream = EventStream(baseURL: client.baseURL, token: client.token)
        stream.start()
        defer { stream.close() }

        let subscription = UUID().uuidString
        for await frame in stream.frames {
            if Task.isCancelled { return }
            switch frame {
            case .ready:
                stream.attach(subscriptionId: subscription, connectionId: found.connectionId)
            case .event(let envelope):
                if case .turnComplete = envelope.event { return }
            case .detached, .closed:
                return
            case .snapshot, .replay, .pong:
                break
            }
        }
    }
}
