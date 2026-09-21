import SwiftUI
import UIKit

/// The bundled Lucide icon font — the web client's icon library
/// (`iconLibrary: "lucide"` in its `components.json`), shipped here as
/// `Resources/Fonts/lucide.ttf` so both clients draw the *same* glyphs instead
/// of an SF Symbol that means roughly the same thing.
///
/// Lucide's glyphs are stroked outlines on a 1000-unit em, drawn from the
/// baseline up (the font has zero descent), with a stroke weight of 2/24 of the
/// box. Rendering at 16pt therefore reproduces the web's `size-4` icon,
/// 1.33pt stroke included — no weight matching needed.
enum LucideFont {
    /// The font's family and PostScript name.
    static let name = "lucide"

    /// Vertical correction applied to every glyph, in fractions of the icon size.
    ///
    /// Icon-font glyphs sit on the text baseline, so inside a square frame the
    /// *line box* gets centered rather than the glyph — which leaves the icon a
    /// fraction low. This is the single knob for that: measure once on a device,
    /// adjust here, and every icon in the app moves together.
    static let baselineNudge: CGFloat = 0

    /// Names of every face the app expects to have registered, for ``verify()``.
    static var requiredFaces: [String] { WebFontFace.all }

    /// Logs any bundled face iOS didn't register — almost always a missing
    /// `UIAppFonts` entry in Info.plist, which otherwise shows up as a silent
    /// fallback to the system font that's easy to miss in a screenshot.
    static func verify() {
        #if DEBUG
        let missing = requiredFaces.filter { UIFont(name: $0, size: 12) == nil }
        if missing.isEmpty { return }
        print(
            """
            [WebTheme] These bundled fonts are not registered: \
            \(missing.joined(separator: ", ")).
            Check the UIAppFonts array in project.yml (info.properties) and that \
            the .ttf files are in CodegiOS/Resources/Fonts.
            """
        )
        #endif
    }
}

/// A Lucide glyph, sized in points like the web sizes it in pixels
/// (`size-4` → 16, `size-3` → 12).
///
/// Color comes from the surrounding `foregroundStyle`, exactly as it does for an
/// SF Symbol, so existing call sites keep their tint when migrated.
struct LucideIcon: View {
    let icon: Lucide
    var size: CGFloat = WebTheme.Size.icon
    /// The Dynamic Type curve the icon scales along. Match it to the text the
    /// icon sits next to, so a caption's icon doesn't outgrow its caption.
    var relativeTo: Font.TextStyle = .body
    /// Draw inside a square of `size × size`. Off for icons inline in prose,
    /// where the natural glyph advance should apply.
    var boxed: Bool = true

    init(
        _ icon: Lucide,
        size: CGFloat = WebTheme.Size.icon,
        relativeTo: Font.TextStyle = .body,
        boxed: Bool = true
    ) {
        self.icon = icon
        self.size = size
        self.relativeTo = relativeTo
        self.boxed = boxed
    }

    /// Migration shim: resolve an SF Symbol name through the port's translation
    /// table. Falls back to the SF Symbol itself for anything unmapped, so a
    /// half-migrated screen still renders something sensible.
    init(
        sf systemName: String,
        size: CGFloat = WebTheme.Size.icon,
        relativeTo: Font.TextStyle = .body
    ) {
        self.init(
            Lucide.forSFSymbol(systemName) ?? .circleHelp,
            size: size,
            relativeTo: relativeTo
        )
    }

    var body: some View {
        Text(verbatim: icon.glyph)
            .font(.custom(LucideFont.name, size: size, relativeTo: relativeTo))
            .offset(y: LucideFont.baselineNudge * size)
            .frame(width: boxed ? size : nil, height: boxed ? size : nil)
            // An icon is decoration; the accessible name belongs to the control
            // or label that owns it.
            .accessibilityHidden(true)
    }
}

/// `Label`'s web equivalent: a Lucide glyph and a `text-sm` title, at the
/// spacing the web's menu items and nav rows use (`gap-1.5`).
struct WebLabel: View {
    private let text: Text
    let icon: Lucide
    var iconSize: CGFloat = WebTheme.Size.icon
    var style: WebTheme.TextStyle = .sm
    /// Icons in the web's rows are `text-muted-foreground` even when the label
    /// is `foreground` — that two-tone treatment is a big part of why the
    /// sidebar reads as calm. Off, the glyph inherits the ambient
    /// `foregroundStyle`, which is what a status label wants: the icon and its
    /// text both go red on a failure, green on a success.
    var dimsIcon: Bool = true

    /// UI copy, localized like `Label`'s own title.
    init(
        _ title: LocalizedStringKey,
        icon: Lucide,
        iconSize: CGFloat = WebTheme.Size.icon,
        style: WebTheme.TextStyle = .sm,
        dimsIcon: Bool = true
    ) {
        self.text = Text(title)
        self.icon = icon
        self.iconSize = iconSize
        self.style = style
        self.dimsIcon = dimsIcon
    }

    /// Runtime data — a path, a branch, a server's own message. Not localized,
    /// and not run through Markdown/interpolation parsing.
    init(
        verbatim title: String,
        icon: Lucide,
        iconSize: CGFloat = WebTheme.Size.icon,
        style: WebTheme.TextStyle = .sm,
        dimsIcon: Bool = true
    ) {
        self.text = Text(verbatim: title)
        self.icon = icon
        self.iconSize = iconSize
        self.style = style
        self.dimsIcon = dimsIcon
    }

    var body: some View {
        HStack(spacing: WebTheme.Space.onePointFive) {
            if dimsIcon {
                LucideIcon(icon, size: iconSize)
                    .foregroundStyle(WebTheme.mutedForeground)
            } else {
                LucideIcon(icon, size: iconSize)
            }
            text.webText(style)
        }
    }
}
