import SwiftUI

/// The agent's brand glyph, drawn plain.
///
/// The web's `AgentIcon` is the mark and nothing else — no tinted disc, no ring.
/// Those were added here to give the glyph presence on a glass plate; on a flat
/// surface they read as a second, competing shape, so they're gone. `size` still
/// describes the outer box, so every call site's layout is unchanged.
struct AgentAvatar: View {
    let agent: AgentType
    var size: CGFloat = 36

    var body: some View {
        AgentIcon(agent: agent)
            .frame(width: size * 0.72, height: size * 0.72)
            .frame(width: size, height: size)
    }
}

/// A section-header glyph (folder / Pinned / Running), matching the web's
/// section headers: a `size-3.5` icon in `--muted-foreground`, no container.
struct SectionBadgeIcon: View {
    let systemImage: String
    var tint: Color = WebTheme.mutedForeground
    var size: CGFloat = 26

    var body: some View {
        LucideIcon(sf: systemImage, size: 14)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
    }
}

/// A folder's identity badge: a small solid-color rounded square, the way the
/// web marks folders across its tab bar and conversation cards
/// (`src/components/ui/folder-badge.tsx`).
///
/// The web fills it with the folder's ramp color and puts the name's first
/// character in white on top; ``init(folderID:name:size:)`` reproduces that
/// exactly. The color-only initializer is kept for the call sites that have the
/// folder's color but not its name, and substitutes a white folder glyph.
struct FolderBadge: View {
    private let fill: Color
    private let label: String?
    private let size: CGFloat

    private var cornerRadius: CGFloat { max(4, size * 0.22) }

    /// Color-only: a white folder glyph on the folder's color.
    init(color: Color, size: CGFloat = 40) {
        self.fill = color
        self.label = nil
        self.size = size
    }

    /// The web's badge: the folder's ramp color (derived from its id) with the
    /// name's first letter or digit in white.
    init(folderID: Int, name: String, size: CGFloat = 16) {
        self.fill = WebFolderPalette.color(forFolderID: folderID)
        self.label = WebFolderPalette.label(for: name)
        self.size = size
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay {
                if let label {
                    Text(verbatim: label)
                        .font(WebTheme.sans(size * 0.56, .medium))
                        .foregroundStyle(.white)
                } else {
                    LucideIcon(.folder, size: size * 0.55)
                        .foregroundStyle(.white)
                }
            }
    }
}

/// A rounded tile holding an icon — the Experts and Skills list rows and their
/// detail heroes. Now a `bg-muted` surface with a `--muted-foreground` glyph:
/// the web reserves filled color tiles for identity (folders, agents), not for
/// list decoration.
struct AccentIconTile: View {
    let symbol: String
    var tint: Color = WebTheme.mutedForeground
    var size: CGFloat = 40

    private var cornerRadius: CGFloat { max(6, size * 0.25) }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(WebTheme.muted)
            .frame(width: size, height: size)
            .overlay {
                LucideIcon(sf: symbol, size: size * 0.45)
                    .foregroundStyle(tint)
            }
    }
}

/// Small pill showing a group's item count, used in section headers — the
/// sidebar's `bg-primary/10 text-primary` counter with mono digits so it doesn't
/// jitter as it ticks.
struct CountBadge: View {
    let count: Int

    var body: some View {
        WebCountPill(count: count)
    }
}

/// Compact agent capsule (brand glyph + short name) — the web's
/// `agent-capsule.tsx`: a `bg-muted` pill whose label is muted, with the brand
/// color carried by the glyph alone.
struct AgentBadge: View {
    let agent: AgentType

    var body: some View {
        HStack(spacing: WebTheme.Space.one) {
            AgentIcon(agent: agent).frame(width: 11, height: 11)
            Text(verbatim: agent.shortName)
                .webText(.xs, .medium)
                .foregroundStyle(WebTheme.mutedForeground)
        }
        .padding(.horizontal, WebTheme.Space.two)
        .frame(height: WebTheme.Size.badge)
        .background(WebTheme.muted, in: Capsule(style: .continuous))
    }
}

/// Conversation status capsule: the web's colored status dot plus a muted label.
/// The dot carries the meaning; the text stays neutral, so a list of sessions
/// doesn't turn into a row of colored words.
struct StatusBadge: View {
    let status: ConversationStatus

    var body: some View {
        HStack(spacing: WebTheme.Space.onePointFive) {
            Circle()
                .fill(status.tint)
                .frame(width: 6, height: 6)
            Text(status.label)
                .webText(.xs, .medium)
                .foregroundStyle(WebTheme.mutedForeground)
        }
        .padding(.horizontal, WebTheme.Space.two)
        .frame(height: WebTheme.Size.badge)
        .background(WebTheme.muted, in: Capsule(style: .continuous))
    }
}

/// A live "running" indicator: the in-progress status dot with an expanding
/// ring. The one piece of ambient motion the app keeps — it tells you an agent
/// is working without you reading anything.
struct LivePulse: View {
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(WebStatusPalette.inProgress)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(WebStatusPalette.inProgress, lineWidth: 2)
                    .scaleEffect(animate ? 2.2 : 1)
                    .opacity(animate ? 0 : 0.8)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}
