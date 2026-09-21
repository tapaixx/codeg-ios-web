import SwiftUI
import UIKit

/// The web client's design system, ported to iOS.
///
/// Everything visual in the web app comes from one set of CSS custom properties
/// (`--background`, `--card`, `--muted-foreground`, …) defined per shadcn theme
/// preset in `src/app/globals.css`. `WebTokens.generated.swift` carries those
/// exact values; this file turns them into *dynamic* SwiftUI colors plus the
/// geometry and type scales that sit on top of them.
///
/// Two axes resolve at paint time, so no view has to observe a store or rebuild
/// when the look changes:
///
/// - **Light / dark** — the standard `userInterfaceStyle` trait.
/// - **Theme preset** — a custom `WebThemeTrait` bridged into the SwiftUI
///   environment as `\.webTheme`, injected once in `RootView`. Picking a preset
///   recolors every token in place, the same way switching `data-theme` on the
///   web's `<html>` does.
///
/// Call sites use the semantic name, never a literal: `WebTheme.mutedForeground`,
/// not a gray. That is what makes 12 presets × light/dark free.
enum WebTheme {

    // MARK: - Surfaces

    /// Page background — the web's `bg-background`.
    static let background = token(.background)
    /// Panel/card fill. In light mode this is pure white against a near-white
    /// background; in dark mode it is one step *lighter* than the page.
    static let card = token(.card)
    /// Menus, popovers, sheets — `bg-popover`.
    static let popover = token(.popover)
    /// The sidebar's own background, a half-step off `background`.
    static let sidebar = token(.sidebar)
    /// Subdued fill for secondary surfaces, inline code, and hover states.
    static let muted = token(.muted)
    /// Hover/active fill for rows and menu items.
    static let accent = token(.accent)
    /// Neutral button fill (`bg-secondary`).
    static let secondary = token(.secondary)

    // MARK: - Content

    /// Primary text.
    static let foreground = token(.foreground)
    /// Secondary text — labels, timestamps, meta. The single most-used content
    /// token in the web UI after `foreground`.
    static let mutedForeground = token(.mutedForeground)
    static let cardForeground = token(.cardForeground)
    static let popoverForeground = token(.popoverForeground)
    static let secondaryForeground = token(.secondaryForeground)
    static let accentForeground = token(.accentForeground)
    static let sidebarForeground = token(.sidebarForeground)

    // MARK: - Emphasis

    /// The one high-contrast fill: solid buttons, the user avatar, active marks.
    /// In the grayscale presets this is near-black (light) / near-white (dark),
    /// which is why the web UI reads as monochrome with color used sparingly.
    static let primary = token(.primary)
    /// Legible content on top of `primary`.
    static let primaryForeground = token(.primaryForeground)
    static let sidebarPrimary = token(.sidebarPrimary)
    static let sidebarPrimaryForeground = token(.sidebarPrimaryForeground)

    /// Errors and destructive actions. Note the web never *fills* with this at
    /// full strength — destructive buttons are `bg-destructive/10` with
    /// `text-destructive`. Use ``destructiveSoft`` for the fill.
    static let destructive = token(.destructive)

    // MARK: - Lines

    /// Hairline borders — `border-border`. Already carries its own alpha in dark
    /// mode (`oklch(1 0 0 / 10%)`), so it composites correctly over any surface.
    static let border = token(.border)
    /// Border for input-like controls; also the fill source for `bg-input/30`.
    static let input = token(.input)
    /// Focus ring color.
    static let ring = token(.ring)
    static let sidebarBorder = token(.sidebarBorder)
    static let sidebarAccent = token(.sidebarAccent)
    static let sidebarAccentForeground = token(.sidebarAccentForeground)
    static let sidebarRing = token(.sidebarRing)

    // MARK: - Data

    static let chart1 = token(.chart1)
    static let chart2 = token(.chart2)
    static let chart3 = token(.chart3)
    static let chart4 = token(.chart4)
    static let chart5 = token(.chart5)

    // MARK: - Derived fills
    //
    // The web composes these inline as Tailwind alpha utilities. They're named
    // here so a call site can't drift to a different alpha than the web uses.

    /// `bg-destructive/10` — the destructive button and badge fill.
    static var destructiveSoft: Color { destructive.opacity(0.10) }
    /// `bg-input/30` — the outline button and input field fill.
    static var inputSoft: Color { input.opacity(0.30) }
    /// `ring-foreground/10` — the 1px ring that outlines a Card.
    static var cardRing: Color { foreground.opacity(0.10) }
    /// `ring-ring/50` — the 3px focus ring.
    static var focusRing: Color { ring.opacity(0.50) }
    /// `bg-primary/10` — soft accent fill for counters and selected pills.
    static var primarySoft: Color { primary.opacity(0.10) }

    // MARK: - Semantic status
    //
    // The web has no `--warning`/`--success` token: status colors come from the
    // chart ramp and from Tailwind literals at the call site. These two name the
    // hues the transcript actually needs (running / warning, succeeded) so status
    // never rides on `destructive` or on a hard-coded RGB.

    /// Amber caution — pending review, connecting, modified marks.
    static let warning = Color(
        light: Color(.sRGB, red: 0.79216, green: 0.54118, blue: 0.00000, opacity: 1), // #CA8A04
        dark: Color(.sRGB, red: 0.98431, green: 0.74902, blue: 0.14118, opacity: 1)   // #FBBF24
    )
    /// Green success — completed turns, applied diffs, healthy connections.
    static let success = Color(
        light: Color(.sRGB, red: 0.08627, green: 0.63922, blue: 0.29020, opacity: 1), // #16A34A
        dark: Color(.sRGB, red: 0.29412, green: 0.83137, blue: 0.50196, opacity: 1)   // #4ADE80
    )

    // MARK: - Token plumbing

    /// A dynamic color for `token`, resolved per color scheme *and* per theme
    /// preset at paint time.
    static func token(_ token: WebToken) -> Color {
        Color(UIColor { traits in
            UIColor(
                WebTokens.value(
                    token,
                    theme: traits.webThemeColor,
                    dark: traits.userInterfaceStyle != .light
                ).color
            )
        })
    }
}

// MARK: - Geometry

extension WebTheme {

    /// Tailwind's radius scale, in points (1 CSS px = 1 pt). The names match the
    /// utility classes the web components use, so porting a component is a
    /// transcription: `rounded-2xl` → `WebTheme.Radius.xl2`.
    enum Radius {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 12
        /// `rounded-2xl` — the Card radius.
        static let xl2: CGFloat = 16
        static let xl3: CGFloat = 24
        /// `rounded-4xl` — buttons and badges. At their heights (24–40pt) this
        /// reads as a full pill, which is the web's most recognizable shape.
        static let xl4: CGFloat = 32
        /// shadcn's `--radius` custom property (0.625rem).
        static let base: CGFloat = 10
        /// `rounded-full`.
        static let full: CGFloat = 999
    }

    /// Tailwind's spacing scale (`gap-2` = 8pt). Only the rungs the ported
    /// components actually use.
    enum Space {
        static let px: CGFloat = 1
        static let half: CGFloat = 2    // 0.5
        static let one: CGFloat = 4     // 1
        static let onePointFive: CGFloat = 6
        static let two: CGFloat = 8
        static let three: CGFloat = 12
        static let four: CGFloat = 16
        static let five: CGFloat = 20
        static let six: CGFloat = 24
        static let eight: CGFloat = 32
    }

    /// Standard control heights (`h-9`, `h-8`, …) and the iOS minimum touch
    /// target. The web's default control is 36pt tall, below Apple's 44pt
    /// guidance — ported controls keep the 36pt *visual* and extend the hit area
    /// to ``minTouchTarget`` via `contentShape`, so the look is the web's and the
    /// ergonomics stay iOS.
    enum Size {
        static let control: CGFloat = 36      // h-9
        static let controlSmall: CGFloat = 32 // h-8
        static let controlTiny: CGFloat = 24  // h-6
        static let controlLarge: CGFloat = 40 // h-10
        static let badge: CGFloat = 20        // h-5
        static let icon: CGFloat = 16         // size-4
        static let iconSmall: CGFloat = 12    // size-3
        static let iconLarge: CGFloat = 20    // size-5
        static let minTouchTarget: CGFloat = 44
    }

    /// Screen-level layout rhythm. `screenHMargin` stays at the iOS standard
    /// 16pt so content lines up with the navigation bar's title and buttons —
    /// the web's own gutters are window chrome, not a phone margin.
    enum Layout {
        static let screenHMargin: CGFloat = 16
        static let sectionSpacing: CGFloat = 20
        static let screenTopInset: CGFloat = 8
        static let screenBottomInset: CGFloat = 28
    }

    /// Motion. The web's transitions are short and unfussy (`transition-all`
    /// ≈ 150ms ease); these are the SwiftUI equivalents, kept as one vocabulary
    /// so durations don't drift per screen.
    enum Motion {
        /// Bars, chips, toggles — the house spring.
        static let chrome = Animation.snappy(duration: 0.22)
        /// Loading ↔ loaded swaps; no overshoot.
        static let content = Animation.smooth(duration: 0.26)
        /// Disclosure.
        static let expand = Animation.snappy(duration: 0.20)
        /// Press feedback — fast enough to feel like a real button.
        static let press = Animation.snappy(duration: 0.10)
        static let scroll = Animation.snappy(duration: 0.30)
    }
}

// MARK: - Typography

/// The bundled faces, addressed by PostScript name. Each weight is a separate
/// static face rather than one variable font: `Font.custom(_:size:)` resolves a
/// PostScript name exactly, while asking a variable font for a weight relies on
/// synthesis that differs across iOS versions.
enum WebFontFace {
    static let sansRegular = "Inter-Regular"
    static let sansMedium = "Inter-Medium"
    static let sansSemibold = "Inter-SemiBold"
    static let sansBold = "Inter-Bold"
    static let monoRegular = "JetBrainsMono-Regular"
    static let monoMedium = "JetBrainsMono-Medium"
    static let monoBold = "JetBrainsMono-Bold"

    /// Every bundled family name, for a launch-time sanity check.
    static let all = [
        sansRegular, sansMedium, sansSemibold, sansBold,
        monoRegular, monoMedium, monoBold, LucideFont.name,
    ]
}

extension WebTheme {

    /// The four weights the web UI actually uses: 400 body, 500 labels and
    /// buttons, 600 titles, 700 headings.
    enum Weight {
        case regular, medium, semibold, bold

        var sansFace: String {
            switch self {
            case .regular: WebFontFace.sansRegular
            case .medium: WebFontFace.sansMedium
            case .semibold: WebFontFace.sansSemibold
            case .bold: WebFontFace.sansBold
            }
        }

        var monoFace: String {
            switch self {
            case .regular: WebFontFace.monoRegular
            case .medium, .semibold: WebFontFace.monoMedium
            case .bold: WebFontFace.monoBold
            }
        }
    }

    /// Inter at an exact point size, still scaling with Dynamic Type.
    ///
    /// `relativeTo` picks the scaling *curve*, not the size: at the default
    /// content size the result is exactly `size` points — the web's number — and
    /// it grows from there for users who enlarge text.
    static func sans(
        _ size: CGFloat,
        _ weight: Weight = .regular,
        relativeTo textStyle: Font.TextStyle? = nil
    ) -> Font {
        .custom(weight.sansFace, size: size, relativeTo: textStyle ?? scalingStyle(for: size))
    }

    /// JetBrains Mono — code, paths, IDs, token counts.
    static func mono(
        _ size: CGFloat,
        _ weight: Weight = .regular,
        relativeTo textStyle: Font.TextStyle? = nil
    ) -> Font {
        .custom(weight.monoFace, size: size, relativeTo: textStyle ?? scalingStyle(for: size))
    }

    /// Maps a point size onto the Dynamic Type curve closest to it, so a 12pt
    /// caption and a 24pt heading don't scale at the same rate.
    private static func scalingStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<13: .caption
        case ..<15: .subheadline
        case ..<17.5: .body
        case ..<21: .title3
        case ..<26: .title2
        default: .title
        }
    }

    /// The web's type scale. Each style is a size + the extra leading needed to
    /// hit Tailwind's line-height for that step (SwiftUI's default line box is
    /// tighter than the web's, which is what makes an unstyled port feel cramped).
    ///
    /// Apply with `.webText(.sm)` rather than setting `.font` directly, so the
    /// line spacing travels with the size.
    struct TextStyle {
        let size: CGFloat
        let weight: Weight
        let lineSpacing: CGFloat
        let tracking: CGFloat
        let isMono: Bool

        init(
            size: CGFloat,
            weight: Weight = .regular,
            lineSpacing: CGFloat = 0,
            tracking: CGFloat = 0,
            isMono: Bool = false
        ) {
            self.size = size
            self.weight = weight
            self.lineSpacing = lineSpacing
            self.tracking = tracking
            self.isMono = isMono
        }

        var font: Font {
            isMono ? WebTheme.mono(size, weight) : WebTheme.sans(size, weight)
        }

        func weight(_ weight: Weight) -> TextStyle {
            TextStyle(
                size: size, weight: weight, lineSpacing: lineSpacing,
                tracking: tracking, isMono: isMono
            )
        }
    }
}

extension WebTheme.TextStyle {
    /// `text-3xs` — 10pt. Micro labels; the web defines it as a custom utility.
    static let xs3 = WebTheme.TextStyle(size: 10, weight: .medium)
    /// `text-2xs` — 11pt. Badge counters, gutter numbers.
    static let xs2 = WebTheme.TextStyle(size: 11, weight: .medium)
    /// `text-xs` — 12pt. Timestamps, badges, meta rows. Very heavily used.
    static let xs = WebTheme.TextStyle(size: 12, lineSpacing: 4)
    /// `text-sm` — 14pt. **The web's default UI size**: rows, buttons, menus,
    /// most body copy.
    static let sm = WebTheme.TextStyle(size: 14, lineSpacing: 6)
    /// `text-base` — 16pt. Card titles and reading prose.
    static let base = WebTheme.TextStyle(size: 16, lineSpacing: 8)
    static let lg = WebTheme.TextStyle(size: 18, weight: .medium, lineSpacing: 10)
    static let xl = WebTheme.TextStyle(size: 20, weight: .semibold, lineSpacing: 8, tracking: -0.2)
    static let xl2 = WebTheme.TextStyle(size: 24, weight: .semibold, lineSpacing: 8, tracking: -0.4)

    /// Message prose — `text-sm` with the transcript's comfortable leading.
    static let body = WebTheme.TextStyle(size: 14, lineSpacing: 7)
    /// Inline and fenced code.
    static let code = WebTheme.TextStyle(size: 12.5, lineSpacing: 4, isMono: true)
    /// Dense diff rows.
    static let diff = WebTheme.TextStyle(size: 11.5, lineSpacing: 2, isMono: true)
}

extension View {
    /// Applies a web text style — font, leading, and tracking together.
    func webText(_ style: WebTheme.TextStyle) -> some View {
        self
            .font(style.font)
            .lineSpacing(style.lineSpacing)
            .tracking(style.tracking)
    }

    /// Applies a web text style with a one-off weight override.
    func webText(_ style: WebTheme.TextStyle, _ weight: WebTheme.Weight) -> some View {
        webText(style.weight(weight))
    }
}

// MARK: - Theme preset ↔ trait bridge

/// Carries the selected shadcn preset by index, so dynamic `UIColor`s can
/// resolve it exactly the way they resolve light/dark. `affectsColorAppearance`
/// tells UIKit this trait changes color resolution, so every token re-resolves
/// in place when the preset changes — no view teardown, which matters because a
/// teardown would kill live transcript streams.
struct WebThemeTrait: UITraitDefinition {
    static let defaultValue: Int = WebThemeColor.default.storageIndex
    static let affectsColorAppearance = true
    static let name = "Codeg web theme preset"
}

extension WebThemeColor {
    /// The preset's display name. Proper nouns from the shadcn palette, which
    /// the web client doesn't translate either.
    var titleKey: LocalizedStringKey {
        switch self {
        case .neutral: "Neutral"
        case .zinc: "Zinc"
        case .slate: "Slate"
        case .stone: "Stone"
        case .gray: "Gray"
        case .red: "Red"
        case .rose: "Rose"
        case .orange: "Orange"
        case .green: "Green"
        case .blue: "Blue"
        case .yellow: "Yellow"
        case .violet: "Violet"
        }
    }

    /// This preset's `--primary`, resolved for an explicit scheme rather than
    /// through the trait. For views the trait bridge can't reach — anything in a
    /// separately-presented hosting controller, i.e. the iPad Settings sheet —
    /// and for a picker swatch, which must show its own preset's color rather
    /// than the active one.
    func primary(dark: Bool) -> Color {
        WebTokens.value(.primary, theme: self, dark: dark).color
    }

    /// The legible content color on top of ``primary(dark:)``.
    func primaryForeground(dark: Bool) -> Color {
        WebTokens.value(.primaryForeground, theme: self, dark: dark).color
    }

    /// Position in `allCases` — the trait's transport value. Persistence uses
    /// `rawValue` (a stable string) instead, so reordering the presets can never
    /// silently reinterpret a saved choice.
    var storageIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    init(storageIndex: Int) {
        let all = Self.allCases
        self = all.indices.contains(storageIndex) ? all[storageIndex] : .default
    }
}

extension UITraitCollection {
    var webThemeColor: WebThemeColor { WebThemeColor(storageIndex: self[WebThemeTrait.self]) }
}

/// Bridges `\.webTheme` in the SwiftUI environment to `WebThemeTrait`. Writing
/// the environment value writes through to the trait collection, which
/// propagates to descendants *and to presented sheets* — the reason this is a
/// trait rather than a plain environment key.
struct WebThemeKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    static let defaultValue: WebThemeColor = .default

    static func read(from traitCollection: UITraitCollection) -> WebThemeColor {
        traitCollection.webThemeColor
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: WebThemeColor) {
        mutableTraits[WebThemeTrait.self] = value.storageIndex
    }
}

extension EnvironmentValues {
    /// The active shadcn theme preset. Set once at the app root.
    var webTheme: WebThemeColor {
        get { self[WebThemeKey.self] }
        set { self[WebThemeKey.self] = newValue }
    }
}

// MARK: - Color helpers

extension Color {
    /// A dynamic color that resolves to `light` or `dark` per the active
    /// `userInterfaceStyle`, re-resolving when the scheme flips at runtime.
    init(light: Color, dark: Color) {
        self = Color(UIColor { $0.userInterfaceStyle == .light ? UIColor(light) : UIColor(dark) })
    }

    /// Parse a `#RRGGBB` / `RRGGBB` (optionally `#RRGGBBAA`) hex string — the
    /// format the server uses for folder colors. Returns nil on anything else.
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8,
              let value = UInt64(hex, radix: 16) else { return nil }
        let r, g, b, a: Double
        if hex.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self = Color(red: r, green: g, blue: b, opacity: a)
    }
}
