import Foundation

/// A destination named by a deep link or a Live Activity record. In the web
/// shell only `.conversation` leads anywhere specific; the rest open the
/// workspace.
enum Route: Hashable {
    case conversation(Int)
    case project(Int)
    /// The "start a new task" screen: a blank session detail. The agent, folder,
    /// and config are chosen in-page (from the nav-bar agent button), and the
    /// first send connects + prompts before a server conversation id exists
    /// (it adopts one on `conversation_linked`).
    case newSession(NewSessionRequest)
}

/// A draft new-task token. Carries only an optional preselected folder (e.g.
/// when launched from a project); the agent/folder/first message are all chosen
/// on the session screen itself, so this is just a stable identity for the
/// pushed/pending draft.
struct NewSessionRequest: Hashable, Identifiable {
    let id: UUID
    var preselectedFolderID: Int?

    init(id: UUID = UUID(), preselectedFolderID: Int? = nil) {
        self.id = id
        self.preselectedFolderID = preselectedFolderID
    }
}

extension Route {
    /// Parse a `codegweb://` deep link: `codegweb://conversation/<id>` and
    /// `codegweb://project/<id>`. (`codegweb://tab/<name>` switches tabs rather than
    /// pushing, so `AppModel.handle(url:)` deals with it before calling this.)
    static func from(url: URL) -> Route? {
        guard url.scheme?.lowercased() == "codegweb" else { return nil }
        let id = url.pathComponents.count > 1 ? Int(url.pathComponents[1]) : nil
        switch url.host?.lowercased() {
        case "conversation": return id.map { .conversation($0) }
        case "project": return id.map { .project($0) }
        default: return nil
        }
    }
}
