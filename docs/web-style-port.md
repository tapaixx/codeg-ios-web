# Web-style port: bringing the codeg web client's design system to iOS

> Status: **superseded.** The app now shows the web client itself in a
> `WKWebView` (see the README); the native screens this document restyles are
> no longer reachable and will be removed. Kept for the record of what was
> ported and why the approach was abandoned: a component-by-component
> transcription can match the web's tokens but never its geometry, and it
> chases a moving target.
>
> Original status: foundation landed, screen migration in progress.
> Source of truth for the visual language is the web client
> (`xintaofei/codeg`), not this document — when they disagree, the web wins and
> this document is stale.

## Why

The app shipped with its own look: iOS 26 Liquid Glass surfaces floating over a
dark canvas with two blurred accent glows, San Francisco type at iOS sizes, SF
Symbols, and a 12-way *accent* picker. The web client looks nothing like that.
It is a shadcn/Radix UI on `neutral`: flat opaque surfaces, one hairline border
instead of shadow, Inter at 14/12pt, Lucide icons, and a 12-way *theme preset*
picker where the default presets are pure grayscale.

The goal of this port is not "inspired by" — it is that a screenshot of the two
clients side by side should read as one product.

## What the two systems are made of

| | Web client | iOS app (before) | iOS app (now) |
|---|---|---|---|
| Color | 31 CSS custom properties × 12 shadcn presets × light/dark, in oklch | 1 accent × 12 palettes, hand-picked RGB | the web's tokens, generated |
| Surfaces | `bg-card` + `ring-1 ring-foreground/10`, no shadow | `.glassEffect(.regular)` + hairline + shadow | `bg-card` + 1px ring |
| Page | `bg-background` | near-black + 2 blurred glows | `bg-background` |
| Type | Inter; `text-sm` (14) is the default UI size | SF; `.subheadline` (15) / `.body` (17) | Inter on the web's scale |
| Code | JetBrains Mono | SF Mono | JetBrains Mono |
| Icons | Lucide, `size-4` | SF Symbols | Lucide (font) — *partially migrated* |
| Radius | cards 16, buttons/badges pill | cards 20–26, controls 14 | cards 16, buttons/badges pill |
| Press | `active:translate-y-px` | scale 0.98 + dim | 1pt nudge |

## Architecture

```
CodegiOS/DesignSystem/
  Web/
    WebTokens.generated.swift    744 color values — generated, never hand-edited
    WebPalette.generated.swift   Tailwind ramp: status dots, folder colors
    LucideIcons.generated.swift  168 icons + the SF Symbol translation table
    WebTheme.swift               token accessors, trait bridge, geometry, type
    WebComponents.swift          shadcn components as SwiftUI
    Lucide.swift                 the icon font view
  Theme.swift                    the old facade, now resolving to WebTheme
  …                              the app's shared primitives, re-cut
scripts/
  gen-web-tokens.mjs             globals.css → WebTokens/WebPalette
  gen-lucide-icons.mjs           lucide codepoints → LucideIcons
  sf-to-lucide.json              the icon mapping (edit this to add an icon)
  port-glass-surfaces.mjs        one-shot codemod: glass → web surfaces
  port-fonts.mjs                 one-shot codemod: SF text styles → Inter scale
  port-icons.mjs                 one-shot codemod: SF Symbols → Lucide
```

### Color

`scripts/gen-web-tokens.mjs` reads the web client's `src/app/globals.css` and
emits every `[data-theme="…"]` block as Swift. The CSS values are `oklch()`,
which iOS has no equivalent for, so the generator converts them with the
**CSS Color 4 gamut-mapping algorithm** — chroma reduction under a deltaEOK ≤
0.02 binary search, not a naive clamp, which would shift the hue of the
saturated presets. Spot-checking the output against Tailwind's published hexes
(zinc-900 `#18181B`, blue-600 `#155DFC`, violet-500 `#8E51FF`) matches exactly.

Re-run after any web theme change:

```bash
node scripts/gen-web-tokens.mjs [path/to/codeg/src/app/globals.css]
```

It defaults to `../codeg-web/src/app/globals.css` (a sibling checkout) and fails
loudly if a preset or a token goes missing rather than silently emitting a hole.

At runtime, a token is a *dynamic* color resolving two traits at paint time:
`userInterfaceStyle` for light/dark and a custom `WebThemeTrait` for the preset.
`RootView` injects the preset once via `\.webTheme`; nothing else observes it, so
changing the theme recolors the app in place without tearing down live
transcript streams.

**Caveat:** the bridged trait does not reach a separately-presented hosting
controller — the iPad Settings *sheet*. Views rendered there that must show a
specific preset's color (the Appearance picker and its preview) resolve it
explicitly with `WebThemeColor.primary(dark:)`. This pre-dates the port; the
same workaround was there for the old accent trait.

### Typography

Inter and JetBrains Mono ship as static faces (`Resources/Fonts/`), addressed by
PostScript name — asking a variable font for a weight relies on synthesis that
differs across iOS versions. Registration is the `UIAppFonts` array in
`project.yml`; `LucideFont.verify()` logs any face iOS didn't register on
launch in DEBUG, because a missing entry otherwise degrades to San Francisco
silently.

Sizes are the web's CSS pixel values read as points, wrapped in
`Font.custom(_:size:relativeTo:)` so they still scale with Dynamic Type. The
mapping the codemod applied:

| SwiftUI style | was | now | web equivalent |
|---|---|---|---|
| `.largeTitle` | 34 | 24 bold | `text-2xl` |
| `.title` | 28 | 20 bold | `text-xl` |
| `.title2` | 22 | 18 semibold | `text-lg` |
| `.title3` | 20 | 16 semibold | `text-base` |
| `.headline` | 17 semibold | 14 semibold | `text-sm font-semibold` |
| `.body` / `.callout` / `.subheadline` | 17 / 16 / 15 | 14 | `text-sm` |
| `.footnote` / `.caption` | 13 / 12 | 12 | `text-xs` |
| `.caption2` | 11 | 11 | `text-2xs` |

This is a real density change, and the intended one: the web's transcript is
14pt where the app's was 17pt.

### Icons

The bundled `lucide.ttf` is the same icon set the web imports from
`lucide-react`, so the glyphs are identical rather than similar — including
stroke weight, which is baked at Lucide's 2/24 ratio and therefore correct at
any size. `scripts/sf-to-lucide.json` holds the SF Symbol → Lucide mapping (96
entries) plus an `extras` list; the generator validates every name against the
font and fails on a typo.

Two ways to draw one:

```swift
LucideIcon(.gitBranch, size: 14)     // preferred — typed, checked at compile time
LucideIcon(sf: "arrow.triangle.branch")  // migration shim, resolves via the table
```

`circle.fill` is deliberately unmapped: the web draws status dots as shapes, not
icons. Use `WebStatusDot`.

## What landed

- **Color**: all 12 presets × light/dark, generated from the web's CSS. The old
  `AccentPalette` is gone; `AppearanceStore.themeColor` replaces it and migrates
  an existing install's accent choice to the nearest preset on first launch.
- **Type**: Inter + JetBrains Mono bundled; 445 `.font(…)` call sites rewritten
  onto the web's scale by `scripts/port-fonts.mjs`.
- **Surfaces**: every `.glassEffect` and `.buttonStyle(.glass…)` in the app is
  gone (39 sites, `scripts/port-glass-surfaces.mjs`); `CodegBackground` is a flat
  `--background` fill with no glows.
- **Icons**: `lucide.ttf` bundled, 185 glyphs typed, 142 SF Symbols mapped; the
  codemod's 102 call sites (`scripts/port-icons.mjs`) plus the per-screen pass
  over everything it skipped — the dynamic `Image(systemName: expr)` forms, the
  unsized ones, and the `Label(…, systemImage:)` rewrites. **Every glyph on the
  app's own canvas is now Lucide.** What still draws an SF Symbol is exactly the
  system surfaces (12 toolbar buttons, 33 menu items, 10 context-menu items, 1
  alert), the tab bar and iPad sidebar `List` rows, and two `.resizable()`
  fallbacks (`AgentIcon`'s missing-asset path, an `AsyncImage` placeholder).
  Every icon-name string literal in the sources now resolves through
  `sf-to-lucide.json`, so no call site can silently land on `circleHelp`.
- **Components**: `WebComponents.swift` ports Button (6 variants × 7 sizes),
  Badge, Card, Tabs, Switch, Input, Separator, Skeleton, the sidebar row, the
  conversation rail, the status dot, chips, section headers, and count pills.
- **Shared primitives re-cut**: `GlassCard` / `FlatCard` / `GlassRow` /
  `PrimaryGlassButton` / `FilterChip` / `EditorSection` / `FieldRow` /
  `SelectBox` / settings rows / empty, loading and error states / badges and
  avatars. Their *names and signatures are unchanged* — only what they draw —
  which is what let ~1,200 call sites change appearance without being touched.
- **`Theme` is now a facade over `WebTheme`**, member by member, each documented
  with the CSS property it resolves to.
- **Status and folder colors** come from the web's own tables
  (`STATUS_COLORS`, `FOLDER_COLORS`), so a session that reads amber on the
  desktop reads amber here. Note the web's mapping is not the intuitive one:
  in-progress is yellow and *cancelled* is red.
- **Pilot screen**: `SessionRow` is a full port of the web's
  `sidebar-conversation-card.tsx` — a 31pt pill row on a 2pt rail with the agent
  glyph on the axis and the status dot notched into it.
- **The composer** (`ComposeBar.swift`) is the web's `codeg-composer-chrome`: one
  `rounded-xl` box on `border-foreground/20`, holding the thumbnails, the field,
  and an action row *inside* the border — a 24pt ghost `+` on the left, a 32pt
  primary Send on the right, swapping to a destructive Square in flight. Focus
  swaps the border to `--ring` and adds the 3pt `ring-ring/50`; tapping the
  box's blank chrome focuses the field, as it does on the web. The bar no longer
  narrows when idle — the web's composer is a box in the column, not a floating
  pill — and the last `GlassEffectContainer` in the app went with it.
- **Session groups** have no card. `SessionSectionCard` is now a section header
  over a plain column, the way the web's sidebar is built; the iOS
  zoom-to-fullscreen interaction it wraps is untouched. `WebSectionHeader` was
  corrected to the web's real treatment while wiring it up: 14pt **regular** at
  `sidebar-foreground/50` in a 32pt row, not the 11pt muted step this document
  used to claim (see `sidebar-section-header.tsx`, whose own comment explains
  that "looks a different size" was contrast, not size).

## What remains

The icon pass, the composer and the session-list sections are done (see above).
What is left, roughly in the order that pays off:

1. **The transcript** (`SessionDetail/Rendering/*`). Tool cards, diffs and plan
   cards use the web's colors, type and icons but keep their old **geometry** —
   their own padding, radii and header layout. The web's equivalents are in
   `src/components/message/*`. This is the largest remaining piece by far and
   the one that still makes a transcript screenshot distinguishable from the
   desktop's; it wants a card-by-card pass, not a codemod.
2. **Dynamic Type audit.** Fixed point sizes scale along a curve chosen per size
   (`WebTheme.scalingStyle`); the dense rows (31pt) will need a check at the
   larger accessibility sizes. The composer's new 32pt/24pt action row belongs
   in that sweep.
3. **Touch targets.** The web's controls are 36pt and its rows 31pt, below
   Apple's 44pt guidance. Kept deliberately — it is the look being ported — but
   any control that proves hard to hit should grow its *hit area*, not its box.
   The composer's 24pt `+` is the most exposed one.
4. **Optional, if you want the whole web feature set**: the font picker (the web
   lets you choose the UI/editor/terminal face), the zoom levels, and the
   workspace background image with its surface-opacity slider.

The rule the icon pass ran under, kept here because new screens need it:
**system surfaces keep SF Symbols, app canvas gets Lucide.** A context menu, a
swipe action, and a nav-bar button are UIKit chrome where an SF Symbol is the
*native* glyph and a Lucide one looks imported; a row, a card, a badge, or an
empty state is the app's own canvas, where matching the web matters.

## Conventions for new code

- Reach for `WebTheme.…` tokens, never a literal color. `Theme.…` still works
  and resolves to the same values; new code should prefer the web's names.
- Reach for `WebTheme.sans(…)` / `.webText(.sm)`, never `.font(.subheadline)`.
- Reach for `LucideIcon`, never `Image(systemName:)`.
- Port a web component by transcribing its Tailwind classes: `rounded-2xl` →
  `WebTheme.Radius.xl2`, `gap-2` → `WebTheme.Space.two`, `h-9` →
  `WebTheme.Size.control`. The scales exist so the transcription is mechanical.

## Verification status

This port is written on a Linux host with no Xcode, so **the only compiler that
has ever seen it is CI** (`.github/workflows/unsigned-ipa.yml`, which builds a
Release device app on a macOS runner). A green run means it compiles and links —
nothing more. **Nobody has looked at these screens.** Every visual claim in this
document is a transcription of the web's CSS, not an observation.

To build it yourself:

```bash
xcodegen generate
xcodebuild -project CodegiOS.xcodeproj -scheme CodegiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -skipMacroValidation build
```

Then check, in this order, the things a compiler cannot catch:

1. **Fonts registered** — launch in DEBUG and confirm `LucideFont.verify()` logs
   nothing. If it lists faces, the `UIAppFonts` entries or the resource copy
   phase are wrong, and everything below is moot.
2. **Icon baseline** — Lucide glyphs sit on the text baseline, so inside a square
   frame they can render a fraction low. If they read low next to their labels,
   set `LucideFont.baselineNudge` (one constant, moves every icon together).
3. **Contrast in light mode** — the app was dark-first; the web's light presets
   are near-white. Check the transcript and the diff colors there specifically.
