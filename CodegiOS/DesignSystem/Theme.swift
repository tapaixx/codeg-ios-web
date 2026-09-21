import SwiftUI
import UIKit

/// The app's original token facade, now resolved entirely from the **web
/// client's design tokens** (see ``WebTheme``).
///
/// Every screen in the app reads its colors, radii, and type through this enum,
/// so re-pointing it here is what carries the web look into all of them at once
/// instead of one file at a time. Each member below documents which CSS custom
/// property in the web's `globals.css` it now resolves to.
///
/// New code should prefer ``WebTheme`` directly: its names are the web's names
/// (`mutedForeground`, `card`, `border`), so a component ported from the web
/// reads as a transcription rather than a translation. This facade stays because
/// deleting it would mean touching ~1,200 call sites for no visual gain — and
/// because the mapping is genuinely one-to-one.
enum Theme {

    // MARK: - Backgrounds

    /// `--background`
    static let bg = WebTheme.background
    /// `--card` — panels sitting on `bg`. In the web's dark theme the card is
    /// *lighter* than the page, which is the inverse of the old glass treatment.
    static let bgElevated = WebTheme.card

    /// `--border`. The web has exactly one hairline value, and both of the app's
    /// old stroke tokens now resolve to it — that single, consistent 1px line
    /// (never a shadow) is a defining trait of the look.
    static let surfaceStroke = WebTheme.border
    /// `--border` — see ``surfaceStroke``.
    static let hairline = WebTheme.border

    /// `--muted` — the inset surface for code blocks and diffs. Opaque now, not
    /// a translucent wash, so nested panels stay legible over any backdrop.
    static let codeSurface = WebTheme.muted
    /// `--sidebar-border` — the transcript timeline's spine, drawn the way the
    /// web draws its conversation rails.
    static let rail = WebTheme.sidebarBorder

    /// `--muted` — top-level message-body surfaces (tool cards, plan, reasoning).
    static let surface = WebTheme.muted
    /// `--muted` at 50% — the fainter inset one level deeper.
    static var surfaceNested: Color { WebTheme.muted.opacity(0.5) }

    // MARK: - Text

    /// `--foreground`
    static let textPrimary = WebTheme.foreground
    /// `--muted-foreground` — labels, timestamps, meta.
    static let textSecondary = WebTheme.mutedForeground
    /// `--muted-foreground` at 75%. The web uses one secondary text color and
    /// leans on size and weight for the third tier; this keeps the app's existing
    /// three-tier call sites working without inventing a token the web lacks.
    static var textTertiary: Color { WebTheme.mutedForeground.opacity(0.75) }

    /// `--destructive`
    static let danger = WebTheme.destructive
    /// An amber caution tone — see ``WebTheme/warning``.
    static let warning = WebTheme.warning

    // MARK: - Emphasis

    /// `--primary`.
    ///
    /// Note what this means for the app's look: in the web's grayscale presets
    /// (neutral / zinc / slate / stone / gray — one of which is the default)
    /// `--primary` is near-black in light mode and near-white in dark mode. The
    /// UI therefore reads as **monochrome**, with hue reserved for status. That
    /// is the intended outcome of the port, not a missing accent color: pick one
    /// of the colored presets in Appearance to tint it.
    static let accent = WebTheme.primary
    /// `--primary-foreground` — legible content on an `accent` fill.
    static let onAccent = WebTheme.primaryForeground
    /// `bg-primary/10` — the web's soft selection/highlight wash.
    static var accentDim: Color { WebTheme.primary.opacity(0.10) }

    /// Tailwind's radius scale, narrowed to the four rungs the app's call sites
    /// use. The values are the web's, which are markedly tighter than the old
    /// 26/20/14/10 — cards at 16 and controls at 12 are most of why the ported
    /// screens read as the web app rather than as iOS cards.
    enum Radius {
        /// `rounded-2xl` — cards, sheets, panels.
        static let xl: CGFloat = WebTheme.Radius.xl2
        /// `rounded-2xl` — the web uses one card radius; `lg` and `xl` coincide.
        static let lg: CGFloat = WebTheme.Radius.xl2
        /// `rounded-xl` — rows, inputs, tool cards.
        static let md: CGFloat = WebTheme.Radius.xl
        /// `rounded-lg` — chips and small marks.
        static let sm: CGFloat = WebTheme.Radius.lg
    }

    /// Forwards to ``WebTheme/Motion``.
    enum Motion {
        static let chrome = WebTheme.Motion.chrome
        static let content = WebTheme.Motion.content
        static let expand = WebTheme.Motion.expand
        static let press = WebTheme.Motion.press
        static let scroll = WebTheme.Motion.scroll
    }

    /// Reading-text tokens for message bodies, now on the web's type scale:
    /// Inter at `text-sm` (14pt) for prose with ~1.5 leading, JetBrains Mono for
    /// code. This is a deliberate density change — the web's transcript is
    /// 14pt, where the app's was 17pt.
    ///
    /// Sizes stay fixed in points (the web's own numbers) but scale with Dynamic
    /// Type through `Font.custom(_:size:relativeTo:)`, so accessibility text
    /// sizes still work.
    enum Typography {
        /// `text-sm` — paragraphs, list items, quotes.
        static let messageBody: Font = WebTheme.sans(14)
        /// Extra leading that brings 14pt Inter to the web's 1.5 line-height.
        static let messageLineSpacing: CGFloat = 7
        /// Vertical rhythm between blocks within one message (`space-y-3`).
        static let blockSpacing: CGFloat = 12
        static let listItemSpacing: CGFloat = 4
        /// Blockquote — same size as body, a touch tighter.
        static let quote: Font = WebTheme.sans(14)
        static let quoteLineSpacing: CGFloat = 6
        /// Fenced/console code in a reading context.
        static let code: Font = WebTheme.mono(12.5)
        static let codeLineSpacing: CGFloat = 4

        /// Heading scale, on the web's steps: `text-xl` / `text-lg` /
        /// `text-base` / `text-sm`.
        static func heading(_ level: Int) -> Font {
            switch level {
            case 1: return WebTheme.sans(20, .bold)
            case 2: return WebTheme.sans(18, .bold)
            case 3: return WebTheme.sans(16, .semibold)
            default: return WebTheme.sans(14, .semibold)
            }
        }
        static let headingLineSpacing: CGFloat = 4
        /// Kept for call sites that set weight separately; the sizes above
        /// already carry their weight.
        static func headingWeight(_ level: Int) -> Font.Weight {
            switch level {
            case 1, 2: return .bold
            default:   return .semibold
            }
        }

        // MARK: Metadata / chrome tier

        /// Tool-card / group titles — `text-sm font-medium`.
        static let cardTitle: Font = WebTheme.sans(14, .medium)
        /// The dominant chrome label — footer meta, header chips, relative time.
        /// `text-2xs` (11pt), the size the web's sidebar meta runs at.
        static let metaLabel: Font = WebTheme.sans(11, .medium)
        /// Tiny emphatic labels — mode badges, "N failed", language tags.
        static let microLabel: Font = WebTheme.sans(10, .semibold)
        /// Code chrome (copy button, language header, expand toggles).
        static let codeMeta: Font = WebTheme.mono(10)
        /// Dense diff/code rows.
        static let diffCode: Font = WebTheme.mono(11.5)
        static let diffLineSpacing: CGFloat = 2
        /// Diff line-number gutter.
        static let diffGutter: Font = WebTheme.mono(10)
    }

    /// Forwards to ``WebTheme/Layout``. The 16pt screen margin is iOS's, not the
    /// web's: it lines content up with the navigation bar's title and buttons.
    enum Layout {
        static let screenHMargin: CGFloat = WebTheme.Layout.screenHMargin
        static let sectionSpacing: CGFloat = WebTheme.Layout.sectionSpacing
        static let screenTopInset: CGFloat = WebTheme.Layout.screenTopInset
        static let screenBottomInset: CGFloat = WebTheme.Layout.screenBottomInset
    }
}

// MARK: - Diff palette

/// The diff colors the web client uses, taken from its Monaco rules in
/// `globals.css` (`.codeg-session-diff-line-*`, `.codeg-dirty-diff-*`) — the
/// GitHub palette, not a tinted accent. Deliberately *not* theme-driven: a diff
/// has to read green/red under every preset.
enum DiffPalette {
    /// `#2ea043` / `#3fb950`
    static let addText = Color(
        light: Color(.sRGB, red: 0.18039, green: 0.62745, blue: 0.26275, opacity: 1),
        dark: Color(.sRGB, red: 0.24706, green: 0.72941, blue: 0.31373, opacity: 1)
    )
    /// `#cf222e` / `#f85149`
    static let delText = Color(
        light: Color(.sRGB, red: 0.81176, green: 0.13333, blue: 0.18039, opacity: 1),
        dark: Color(.sRGB, red: 0.97255, green: 0.31765, blue: 0.28627, opacity: 1)
    )
    /// `#1f6feb` / `#388bfd` — modified marks in the file tree and gutters.
    static let modifiedText = Color(
        light: Color(.sRGB, red: 0.12157, green: 0.43529, blue: 0.92157, opacity: 1),
        dark: Color(.sRGB, red: 0.21961, green: 0.54510, blue: 0.99216, opacity: 1)
    )
    /// `rgba(46,160,67,0.14)` / `rgba(63,185,80,0.18)`
    static let addBg = Color(
        light: Color(.sRGB, red: 0.18039, green: 0.62745, blue: 0.26275, opacity: 0.14),
        dark: Color(.sRGB, red: 0.24706, green: 0.72941, blue: 0.31373, opacity: 0.18)
    )
    /// `rgba(207,34,46,0.12)` / `rgba(248,81,73,0.2)`
    static let delBg = Color(
        light: Color(.sRGB, red: 0.81176, green: 0.13333, blue: 0.18039, opacity: 0.12),
        dark: Color(.sRGB, red: 0.97255, green: 0.31765, blue: 0.28627, opacity: 0.20)
    )
}

// MARK: - Fonts

extension Font {
    /// Monospaced face for code, file paths, IDs, and token counts — the web's
    /// bundled JetBrains Mono, not the system monospace.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        WebTheme.mono(size, weight == .regular ? .regular : (weight == .bold ? .bold : .medium))
    }
}

extension View {
    /// A 1px `--border` hairline — the web's only surface-definition device.
    func hairlineBorder(_ cornerRadius: CGFloat, color: Color = WebTheme.border) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(color, lineWidth: 1)
        )
    }
}
