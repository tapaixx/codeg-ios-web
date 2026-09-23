import Foundation

/// The server's global side-channel, as one long-lived WebSocket.
///
/// Every `/ws/events` socket receives the server's global broadcasts as
/// `{ "channel": …, "payload": … }` frames, no subscription needed — that is
/// how the web client's sidebar learns about a conversation another client
/// started. This hub reads just one of those channels, `conversation://changed`,
/// and hands its upserts / status flips / deletions to whoever is listening
/// (``RunningTurnWatcher``), so a turn that starts anywhere is known here
/// within a round-trip rather than at the next 25-second poll.
///
/// It attaches to nothing and begins no background turn: it is a listener,
/// not a session. Reconnects forever with a capped backoff while it is
/// running; the broadcaster drops what it can't deliver, so the poll stays as
/// the safety net for anything missed during a gap.
///
/// Coupling note: the server calls this frame shape "legacy" and plans to
/// retire it once every transport uses the attach protocol. If it goes, this
/// hub sees nothing and the watcher falls back to polling — nothing breaks,
/// it just gets slower.
final class ServerEventHub: @unchecked Sendable {
    enum Change: Sendable {
        case upsert(ConversationSummary)
        case status(id: Int, status: ConversationStatus)
        case deleted(id: Int)
    }

    let changes: AsyncStream<Change>
    private let continuation: AsyncStream<Change>.Continuation
    private let url: URL
    private let token: String
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var generation = 0
    private var isClosed = false
    private var failures = 0

    private static let channel = "conversation://changed"
    private static let pingInterval: TimeInterval = 20

    init(baseURL: URL, token: String) {
        self.url = EventStream.websocketURL(from: baseURL)
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var captured: AsyncStream<Change>.Continuation!
        self.changes = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        self.continuation = captured
    }

    func start() { open() }

    func close() {
        lock.lock()
        guard !isClosed else { lock.unlock(); return }
        isClosed = true
        generation &+= 1
        let t = task
        task = nil
        lock.unlock()
        t?.cancel(with: .goingAway, reason: nil)
        continuation.finish()
    }

    // MARK: - Socket

    private func open() {
        lock.lock()
        guard !isClosed else { lock.unlock(); return }
        generation &+= 1
        let gen = generation
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("codeg-events", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let socket = EventStream.streamSession.webSocketTask(with: request)
        task = socket
        lock.unlock()

        socket.resume()
        receive(gen, socket)
        schedulePing(gen)
    }

    private func isCurrent(_ gen: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !isClosed && gen == generation
    }

    private func receive(_ gen: Int, _ socket: URLSessionWebSocketTask) {
        guard isCurrent(gen) else { return }
        socket.receive { [weak self] result in
            guard let self, self.isCurrent(gen) else { return }
            switch result {
            case .failure:
                self.reconnect(gen)
            case .success(let message):
                self.handle(message)
                self.receive(gen, socket)
            }
        }
    }

    private func schedulePing(_ gen: Int) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.pingInterval) { [weak self] in
            guard let self, self.isCurrent(gen) else { return }
            self.lock.lock(); let socket = self.task; self.lock.unlock()
            socket?.sendPing { [weak self] error in
                guard let self, self.isCurrent(gen) else { return }
                if error != nil { self.reconnect(gen) } else { self.schedulePing(gen) }
            }
        }
    }

    private func reconnect(_ gen: Int) {
        lock.lock()
        guard !isClosed, gen == generation else { lock.unlock(); return }
        generation &+= 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        failures += 1
        let delay = min(30, pow(2, Double(min(failures - 1, 5))))
        let attempt = failures
        lock.unlock()
        AppConsole.log("Event hub disconnected; retry \(attempt) in \(Int(delay))s", level: .warn)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.open()
        }
    }

    // MARK: - Frames

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: return
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channel = obj["channel"] as? String else { return }
        // Any frame at all means the link is healthy.
        lock.lock(); let recovered = failures > 0; failures = 0; lock.unlock()
        if recovered || channel == "__ready__" { AppConsole.log("Event hub connected") }
        guard channel == Self.channel,
              let payload = obj["payload"] as? [String: Any],
              let kind = payload["kind"] as? String else { return }

        switch kind {
        case "upsert":
            guard let summary = payload["summary"],
                  let raw = try? JSONSerialization.data(withJSONObject: summary),
                  let decoded = try? CodegJSON.decoder.decode(ConversationSummary.self, from: raw) else { return }
            continuation.yield(.upsert(decoded))
        case "status":
            guard let id = payload["id"] as? Int, let status = payload["status"] as? String else { return }
            continuation.yield(.status(id: id, status: ConversationStatus(rawValue: status) ?? .other))
        case "deleted":
            guard let id = payload["id"] as? Int else { return }
            continuation.yield(.deleted(id: id))
        default:
            break
        }
    }
}
