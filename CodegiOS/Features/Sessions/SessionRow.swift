import SwiftUI

/// One conversation row in ``SessionListView`` / ``ActivityView``, ported from
/// the web client's `sidebar-conversation-card.tsx`.
///
/// The web's row is the most distinctive thing in its UI, and it's all
/// structure rather than decoration: a 31pt full-pill row, transparent at rest,
/// with a 2pt vertical rail running its full height and the agent's 12pt brand
/// glyph sitting *on* the rail, a status dot notched into the glyph's corner.
/// Selected rows take a `bg-sidebar-primary/8` wash — no border, no card, no
/// shadow. Consecutive rows' rails join into one continuous line, which is what
/// makes a long session list read as a single thread instead of a stack of
/// cards.
struct SessionRow: View {
    let conversation: ConversationSummary
    let isSelected: Bool
    /// A dim folder tag shown before the timestamp, or `nil` to omit it (e.g.
    /// inside a Chats folder group, where the folder is already the header).
    /// Used by Activity/Search and the cross-folder Pinned group for context.
    var folderName: String?
    /// Tap handler. When `nil`, the row is a non-interactive preview (no Button,
    /// no context menu) — used inside ``SessionSectionCard``'s capped preview,
    /// where the whole card owns the tap.
    var onTap: (() -> Void)? = nil
    /// When set, a long-press context menu offers Pin/Unpin (the label reflects
    /// `conversation.isPinned`). `.swipeActions` doesn't work inside the list's
    /// `LazyVStack`, so a context menu is the toggle affordance.
    var onTogglePin: (() -> Void)?

    /// The web's row height (`h-[1.9375rem]`).
    private static let rowHeight: CGFloat = 31

    var body: some View {
        if let onTap {
            Button(action: onTap) { rowContent }
                .buttonStyle(.webRow(selected: isSelected, height: Self.rowHeight))
                .contextMenu {
                    if let onTogglePin {
                        Button(action: onTogglePin) {
                            Label(conversation.isPinned ? "Unpin" : "Pin",
                                  systemImage: conversation.isPinned ? "pin.slash" : "pin")
                        }
                    }
                }
        } else {
            // Display-only preview (inside SessionSectionCard): the whole card
            // owns the tap, so the row renders without a Button or context menu.
            rowContent
                .frame(height: Self.rowHeight)
        }
    }

    /// The row's visual content, shared by the interactive (Button) rendering and
    /// the non-interactive preview rendering.
    private var rowContent: some View {
        HStack(spacing: WebTheme.Space.two) {
            railMarker

            (conversation.trimmedTitle.map { Text(verbatim: $0) } ?? Text("Untitled session"))
                .webText(.sm)
                .foregroundStyle(WebTheme.sidebarForeground)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let folderName {
                Text(verbatim: folderName)
                    .webText(.xs)
                    .foregroundStyle(WebTheme.mutedForeground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 96, alignment: .trailing)
            }

            trailing
        }
        .padding(.trailing, WebTheme.Space.two)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The rail, the agent glyph on its axis, and the status dot notched into
    /// the glyph's trailing-bottom corner — the web's exact construction.
    private var railMarker: some View {
        WebRailMarker(glyphSize: 12) {
            AgentIcon(agent: conversation.agentType)
                .overlay(alignment: .bottomTrailing) {
                    WebStatusDot(
                        color: conversation.status.tint,
                        size: 5,
                        ringColor: WebTheme.sidebar
                    )
                    .offset(x: 2, y: 2)
                }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if conversation.status.isLive {
            LivePulse()
        } else {
            Text(RelativeTime.compact(from: conversation.updatedAt))
                .webText(.xs2)
                .monospacedDigit()
                .foregroundStyle(WebTheme.mutedForeground)
                .fixedSize()
        }
    }
}

// MARK: - Relative time

/// Compact relative-time formatting shared by rows.
///
/// `RelativeDateTimeFormatter` is not `Sendable`, so the shared instance is
/// pinned to the main actor — every caller here renders from a SwiftUI view
/// body, which is already main-actor isolated.
@MainActor
enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.dateTimeStyle = .numeric
        return f
    }()

    /// Phrased relative time ("2h ago", "now", "in 5m") for prose contexts.
    static func string(from date: Date, relativeTo reference: Date = Date()) -> String {
        let interval = reference.timeIntervalSince(date)
        if interval >= 0, interval < 45 { return "now" }
        return formatter.localizedString(for: date, relativeTo: reference)
    }

    /// Ultra-compact magnitude for dense list rows: "now", "5m", "2h", "6d",
    /// then a short date ("Mar 5") past a week. No "ago"/"in" suffix.
    static func compact(from date: Date, relativeTo reference: Date = Date()) -> String {
        let interval = reference.timeIntervalSince(date)
        if interval < 60 { return "now" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
