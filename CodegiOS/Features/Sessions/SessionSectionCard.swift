import SwiftUI

/// One session group (Pinned / a folder / Running / Last 24 Hours): a section
/// header plus a capped preview of its rows.
///
/// No card. The web's sidebar has none — a group is a header over a plain
/// column on the page background (`sidebar-section-header.tsx` +
/// `sidebar-conversation-list.tsx`), and the surface that used to wrap this was
/// the last big non-web shape on the app's first screen. What survives the port
/// is the *interaction*, which is iOS's and has no web equivalent: the *whole
/// group* is a single tap target that zoom-expands to a fullscreen list
/// (``SessionSectionFullScreen``) via the host's `.fullScreenCover` +
/// `.navigationTransition(.zoom)`.
///
/// Preview rows are display-only (`SessionRow` with no `onTap`) so the card owns
/// the tap — matching the App Store pattern where you tap the card to open the
/// collection, then tap a row inside it.
struct SessionSectionCard: View {
    let title: String
    /// Kept for the fullscreen drill-in, which still tints its header; the web's
    /// section header itself carries no per-group color, so this no longer
    /// paints anything here.
    var tint: Color = Theme.accent
    let conversations: [ConversationSummary]
    /// Per-row folder tag (return `nil` to omit) — shown on cross-folder groups
    /// like Pinned / Other / Activity, hidden inside a single folder's card.
    var folderName: (ConversationSummary) -> String? = { _ in nil }
    /// How many rows to preview before the "Show all" affordance.
    var previewLimit: Int = 5
    /// Whole-card tap → host presents the fullscreen list.
    let onExpand: () -> Void

    private var hasMore: Bool { conversations.count > previewLimit }

    var body: some View {
        Button(action: onExpand) {
            VStack(alignment: .leading, spacing: 2) {
                header

                ForEach(conversations.prefix(previewLimit)) { conv in
                    // No `onTap` → renders as a non-interactive preview row.
                    SessionRow(
                        conversation: conv,
                        isSelected: false,
                        folderName: folderName(conv)
                    )
                    // The web's conversation list is `px-1.5`; its section
                    // header is `px-2`, so the header sits a hair further in
                    // than the rows it labels.
                    .padding(.horizontal, WebTheme.Space.onePointFive)
                }

                if hasMore {
                    showAllFooter
                        .padding(.horizontal, WebTheme.Space.two)
                        .padding(.top, WebTheme.Space.one)
                }
            }
            .padding(.bottom, WebTheme.Space.three)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(conversations.count) sessions")
        .accessibilityHint("Opens the full list")
    }

    /// The web's section header: the group's name at the list's own 14pt, in
    /// `sidebar-foreground/50`, with a running total as the trailing count pill
    /// the sidebar puts at the end of a nav row. The chevron stands in for the
    /// web's disclosure — here it opens the fullscreen drill-in rather than
    /// collapsing in place, which is what the whole group is a tap target for.
    private var header: some View {
        WebSectionHeader(title: title, expanded: false) {
            WebCountPill(count: conversations.count)
        }
    }

    private var showAllFooter: some View {
        HStack(spacing: WebTheme.Space.one) {
            Spacer(minLength: 0)
            Text("Show all \(conversations.count)")
                .webText(.xs, .medium)
                .foregroundStyle(WebTheme.mutedForeground)
            LucideIcon(.chevronRight, size: WebTheme.Size.iconSmall)
                .foregroundStyle(WebTheme.mutedForeground)
        }
    }
}

/// The fullscreen drill-in a ``SessionSectionCard`` zoom-expands into. It's a real
/// `NavigationStack` so the close affordance is a **native toolbar button** — a
/// custom button floating over a `.navigationTransition(.zoom)` cover does NOT
/// reliably receive taps (the cover's interactive-dismiss layer eats them), which
/// is why an earlier hand-rolled floating "X" did nothing. The nav bar background
/// is hidden so that native close button floats over a clean top (App Store
/// editorial style) above a big left-aligned title with a small "N sessions total"
/// eyebrow. The row list is a `List` (UICollectionView cell recycling) so a
/// many-hundred-row group scrolls without the lazy-stack stutter. Rows are tappable
/// **only here** — a tap reports the id via `onOpen` (the host opens the conversation
/// first — pushing the detail onto the nav stack behind the cover — *then* clears the
/// cover binding, so the cover's dismissal reveals the already-pushed detail in one
/// motion instead of flashing this list); the close button reports via `onClose`.
struct SessionSectionFullScreen: View {
    let title: String
    var tint: Color = Theme.accent
    /// Passed fresh by the host each render (never a frozen snapshot), so a
    /// background refresh while this is open keeps the list current.
    let conversations: [ConversationSummary]
    var folderName: (ConversationSummary) -> String? = { _ in nil }
    let onOpen: (Int) -> Void
    var onTogglePin: ((ConversationSummary) -> Void)?
    /// Dismisses the fullscreen. The host drives this by clearing the cover's
    /// item binding (`expandedSection = nil`) — the same path the row-open flow
    /// uses. `@Environment(\.dismiss)` is a no-op for a cover presented with
    /// `.navigationTransition(.zoom)`, so the close button reports up instead.
    let onClose: () -> Void

    /// "N sessions total" eyebrow shown above the big title.
    private var totalLabel: LocalizedStringKey {
        let n = conversations.count
        return n == 1 ? "1 session total" : "\(n) sessions total"
    }

    var body: some View {
        NavigationStack {
            List {
                header
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 14, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                ForEach(conversations) { conv in
                    SessionRow(
                        conversation: conv,
                        isSelected: false,
                        folderName: folderName(conv),
                        onTap: { onOpen(conv.id) },
                        onTogglePin: onTogglePin.map { toggle in { toggle(conv) } }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .background(CodegBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            // Hidden bar background → the close button floats over a clean top
            // (App Store look) instead of sitting on a visible band above the title.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        LucideIcon(sf: "xmark", size: 15)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    /// Big left-aligned group title with a small total-count eyebrow above it —
    /// no leading icon, no trailing number (the editorial-card look).
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(totalLabel)
                .font(WebTheme.sans(11, .bold))
                .foregroundStyle(tint)
                .tracking(0.8)
                .textCase(.uppercase)
            Text(LocalizedStringKey(stringLiteral: title))
                .font(WebTheme.sans(24, .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        // Keep a long title clear of the floating close button.
        .padding(.trailing, 44)
    }
}
