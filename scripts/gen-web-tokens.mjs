#!/usr/bin/env node
// Generates CodegiOS/DesignSystem/Web/WebTokens.generated.swift from the web
// client's globals.css, so the iOS app's color tokens ARE the web's tokens —
// same 12 shadcn presets, same light/dark pairs, no hand-transcribed hex.
//
//   node scripts/gen-web-tokens.mjs [path/to/codeg/src/app/globals.css]
//
// Default source path assumes the web repo is a sibling checkout:
//   ../codeg-web/src/app/globals.css
//
// The CSS values are `oklch()`, which iOS has no native equivalent for, so this
// converts Oklch → sRGB with the CSS Color 4 gamut-mapping algorithm (chroma
// reduction with a deltaEOK ≤ 0.02 binary search, not a naive clip) — the same
// mapping a browser applies when it paints these colors on an sRGB display.
// Re-run after any theme change on the web side; the .swift file is generated,
// never edited by hand.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO = resolve(HERE, "..")
const SOURCE = resolve(
  process.argv[2] ?? resolve(REPO, "../codeg-web/src/app/globals.css")
)
const OUT = resolve(REPO, "CodegiOS/DesignSystem/Web/WebTokens.generated.swift")
const PALETTE_OUT = resolve(
  REPO,
  "CodegiOS/DesignSystem/Web/WebPalette.generated.swift"
)

// Raw Tailwind ramp colors the web client names directly as utility classes
// rather than through a theme token: conversation status dots (`STATUS_COLORS`
// in src/lib/types.ts) and the 16 folder identity colors (`FOLDER_COLORS` in
// src/lib/folder-badge.ts). Values transcribed from tailwindcss 4.3.3's
// theme.css, and converted below by the same Oklch → sRGB path as the tokens.
const TAILWIND = {
  "red-500": "oklch(63.7% 0.237 25.331)",
  "orange-500": "oklch(70.5% 0.213 47.604)",
  "amber-500": "oklch(76.9% 0.188 70.08)",
  "yellow-400": "oklch(85.2% 0.199 91.936)",
  "yellow-500": "oklch(79.5% 0.184 86.047)",
  "lime-500": "oklch(76.8% 0.233 130.85)",
  "green-500": "oklch(72.3% 0.219 149.579)",
  "emerald-500": "oklch(69.6% 0.17 162.48)",
  "teal-500": "oklch(70.4% 0.14 182.503)",
  "cyan-500": "oklch(71.5% 0.143 215.221)",
  "sky-500": "oklch(68.5% 0.169 237.323)",
  "blue-500": "oklch(62.3% 0.214 259.815)",
  "indigo-500": "oklch(58.5% 0.233 277.117)",
  "violet-500": "oklch(60.6% 0.25 292.717)",
  "purple-500": "oklch(62.7% 0.265 303.9)",
  "fuchsia-500": "oklch(66.7% 0.295 322.15)",
  "pink-500": "oklch(65.6% 0.241 354.308)",
  "gray-400": "oklch(70.7% 0.022 261.325)",
  "gray-500": "oklch(55.1% 0.027 264.364)",
}

/** `FOLDER_COLORS`, in the web's order — the index is part of the identity. */
const FOLDER_COLORS = [
  "red-500",
  "orange-500",
  "amber-500",
  "yellow-500",
  "lime-500",
  "green-500",
  "emerald-500",
  "teal-500",
  "cyan-500",
  "sky-500",
  "blue-500",
  "indigo-500",
  "violet-500",
  "purple-500",
  "fuchsia-500",
  "pink-500",
]

/** `STATUS_COLORS` — conversation status → Tailwind color. */
const STATUS_COLORS = {
  inProgress: "yellow-400",
  pendingReview: "blue-500",
  completed: "green-500",
  cancelled: "red-500",
}

// ---------------------------------------------------------------------------
// Oklch → sRGB (CSS Color 4)
// ---------------------------------------------------------------------------

/** Oklab → linear sRGB (Björn Ottosson's matrices, as specified in CSS Color 4). */
function oklabToLinearSrgb(L, a, b) {
  const l_ = L + 0.3963377774 * a + 0.2158037573 * b
  const m_ = L - 0.1055613458 * a - 0.0638541728 * b
  const s_ = L - 0.0894841775 * a - 1.291485548 * b
  const l = l_ ** 3
  const m = m_ ** 3
  const s = s_ ** 3
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ]
}

function oklchToOklab(L, C, H) {
  const rad = (H * Math.PI) / 180
  return [L, C * Math.cos(rad), C * Math.sin(rad)]
}

/** The sRGB transfer function (linear → gamma-encoded). */
function encodeSrgb(c) {
  const sign = c < 0 ? -1 : 1
  const abs = Math.abs(c)
  return abs <= 0.0031308
    ? 12.92 * c
    : sign * (1.055 * abs ** (1 / 2.4) - 0.055)
}

const IN_GAMUT_EPS = 1e-6
const inGamut = ([r, g, b]) =>
  [r, g, b].every((c) => c >= -IN_GAMUT_EPS && c <= 1 + IN_GAMUT_EPS)

const clip = ([r, g, b]) =>
  [r, g, b].map((c) => Math.min(1, Math.max(0, c)))

/** Perceptual distance in Oklab — the JND metric the gamut search minimizes. */
function deltaEOK(lab1, lab2) {
  const dL = lab1[0] - lab2[0]
  const da = lab1[1] - lab2[1]
  const db = lab1[2] - lab2[2]
  return Math.sqrt(dL * dL + da * da + db * db)
}

function linearSrgbToOklab(r, g, b) {
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ]
}

/**
 * CSS Color 4 §13.2 gamut mapping: keep lightness and hue, walk chroma down
 * until the clipped result is within one JND (0.02 deltaEOK) of the requested
 * color. A plain clamp would shift hue on the saturated presets (red / violet /
 * green primaries), which is exactly what the web theme authors avoided.
 */
function oklchToSrgb(L, C, H) {
  if (L >= 1) return [1, 1, 1]
  if (L <= 0) return [0, 0, 0]

  const direct = oklabToLinearSrgb(...oklchToOklab(L, C, H))
  if (inGamut(direct)) return clip(direct).map(encodeSrgb)

  const JND = 0.02
  const EPSILON = 0.0001
  let min = 0
  let max = C
  let best = clip(direct)

  while (max - min > EPSILON) {
    const chroma = (min + max) / 2
    const current = oklabToLinearSrgb(...oklchToOklab(L, chroma, H))
    if (inGamut(current)) {
      min = chroma
      best = clip(current)
      continue
    }
    const clipped = clip(current)
    const error = deltaEOK(
      linearSrgbToOklab(...clipped),
      linearSrgbToOklab(...current)
    )
    if (error < JND) {
      best = clipped
      if (JND - error < EPSILON) break
      min = chroma
    } else {
      max = chroma
    }
  }

  return best.map(encodeSrgb)
}

// ---------------------------------------------------------------------------
// globals.css parsing
// ---------------------------------------------------------------------------

/** `oklch(0.21 0.006 285.885)` / `oklch(1 0 0 / 10%)` → { r, g, b, a } in 0…1. */
function parseOklch(value) {
  const match = value
    .trim()
    .match(
      /^oklch\(\s*([\d.]+%?)\s+([\d.]+)\s+([\d.]+)\s*(?:\/\s*([\d.]+%?)\s*)?\)$/
    )
  if (!match) return null
  const num = (raw) =>
    raw.endsWith("%") ? parseFloat(raw) / 100 : parseFloat(raw)
  const [r, g, b] = oklchToSrgb(num(match[1]), num(match[2]), num(match[3]))
  return { r, g, b, a: match[4] === undefined ? 1 : num(match[4]) }
}

const css = readFileSync(SOURCE, "utf8")

/** Every `[data-theme="x"] { … }` / `[data-theme="x"].dark { … }` block. */
function parseThemeBlocks(source) {
  const blocks = new Map() // "neutral:light" → Map(token → rgba)
  const header = /\[data-theme="([a-z]+)"\](\.dark)?\s*\{/g
  let match
  while ((match = header.exec(source))) {
    const [, theme, isDark] = match
    const end = source.indexOf("}", match.index)
    if (end === -1) continue
    const body = source.slice(match.index + match[0].length, end)
    // A `[data-theme=…] .some-class {` rule (e.g. the .tu-viz chart overrides)
    // declares no custom properties; those blocks fall out here as empty.
    const tokens = new Map()
    for (const decl of body.split(";")) {
      const colon = decl.indexOf(":")
      if (colon === -1) continue
      const name = decl.slice(0, colon).trim()
      if (!name.startsWith("--")) continue
      const rgba = parseOklch(decl.slice(colon + 1))
      if (rgba) tokens.set(name.slice(2), rgba)
    }
    if (tokens.size === 0) continue
    blocks.set(`${theme}:${isDark ? "dark" : "light"}`, tokens)
  }
  return blocks
}

const blocks = parseThemeBlocks(css)

// Preset order is the web's THEME_COLORS order (src/lib/theme-presets.ts), so
// the iOS appearance picker lists them in the same order as the web's.
const THEMES = [
  "neutral",
  "zinc",
  "slate",
  "stone",
  "gray",
  "red",
  "rose",
  "orange",
  "green",
  "blue",
  "yellow",
  "violet",
]

for (const theme of THEMES) {
  for (const scheme of ["light", "dark"]) {
    if (!blocks.has(`${theme}:${scheme}`)) {
      throw new Error(
        `globals.css is missing the [data-theme="${theme}"]${
          scheme === "dark" ? ".dark" : ""
        } block — did the web theme system change shape?`
      )
    }
  }
}

// The token set is taken from the first block and asserted identical in every
// other one: a preset that grew or lost a token would otherwise generate a Swift
// switch that silently falls back for the odd one out.
const TOKENS = [...blocks.get("neutral:light").keys()]
for (const [key, tokens] of blocks) {
  const missing = TOKENS.filter((t) => !tokens.has(t))
  const extra = [...tokens.keys()].filter((t) => !TOKENS.includes(t))
  if (missing.length || extra.length) {
    throw new Error(
      `token set mismatch in ${key}: missing [${missing}], extra [${extra}]`
    )
  }
}

// ---------------------------------------------------------------------------
// Swift emission
// ---------------------------------------------------------------------------

const camel = (kebab) =>
  kebab.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase())

const f = (n) => n.toFixed(5).replace(/0+$/, "0")

const hex = ({ r, g, b }) =>
  "#" +
  [r, g, b]
    .map((c) =>
      Math.round(Math.min(1, Math.max(0, c)) * 255)
        .toString(16)
        .padStart(2, "0")
    )
    .join("")
    .toUpperCase()

const caseName = (theme) => theme

let out = `// Generated by scripts/gen-web-tokens.mjs — DO NOT EDIT BY HAND.
//
// Source: the web client's src/app/globals.css (${TOKENS.length} tokens ×
// ${THEMES.length} presets × light/dark). Oklch values are converted to sRGB with
// the CSS Color 4 gamut-mapping algorithm, so these are the exact colors a
// browser paints for the same theme. Re-run the generator after a web theme
// change rather than editing a value here.

import SwiftUI

/// One resolved token color, in gamma-encoded sRGB.
struct WebRGBA: Equatable, Sendable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

/// The web's shadcn color presets, in the web's own picker order
/// (\`THEME_COLORS\` in src/lib/theme-presets.ts).
enum WebThemeColor: String, CaseIterable, Identifiable, Sendable {
${THEMES.map((t) => `    case ${caseName(t)} = "${t}"`).join("\n")}

    var id: String { rawValue }

    /// The web's default preset — pure grayscale, zero chroma.
    static let \`default\`: WebThemeColor = .neutral

    /// The swatch shown in the theme picker: this preset's own light \`--primary\`,
    /// resolved independently of the active theme (mirrors \`THEME_COLOR_PREVIEW\`).
    var swatch: Color { WebTokens.value(.primary, theme: self, dark: false).color }
}

/// Every CSS custom property the web theme blocks define.
enum WebToken: String, CaseIterable, Sendable {
${TOKENS.map((t) => `    case ${camel(t)} = "${t}"`).join("\n")}
}

enum WebTokens {
    /// The token table lookup. A nested switch (rather than a dictionary literal)
    /// keeps this cheap to type-check and free of runtime hashing.
    static func value(_ token: WebToken, theme: WebThemeColor, dark: Bool) -> WebRGBA {
        switch (theme, dark) {
${THEMES.flatMap((t) => [
  `        case (.${caseName(t)}, false): return ${camel(t)}Light(token)`,
  `        case (.${caseName(t)}, true): return ${camel(t)}Dark(token)`,
]).join("\n")}
        }
    }

`

for (const theme of THEMES) {
  for (const scheme of ["light", "dark"]) {
    const tokens = blocks.get(`${theme}:${scheme}`)
    const fn = `${camel(theme)}${scheme === "dark" ? "Dark" : "Light"}`
    out += `    private static func ${fn}(_ token: WebToken) -> WebRGBA {\n        switch token {\n`
    for (const name of TOKENS) {
      const rgba = tokens.get(name)
      const args =
        rgba.a === 1
          ? `${f(rgba.r)}, ${f(rgba.g)}, ${f(rgba.b)}`
          : `${f(rgba.r)}, ${f(rgba.g)}, ${f(rgba.b)}, ${f(rgba.a)}`
      out += `        case .${camel(name)}: return WebRGBA(${args}) // ${hex(rgba)}${
        rgba.a === 1 ? "" : ` @${Math.round(rgba.a * 100)}%`
      }\n`
    }
    out += `        }\n    }\n\n`
  }
}

out = out.replace(/\n\n$/, "\n") + "}\n"

mkdirSync(dirname(OUT), { recursive: true })
writeFileSync(OUT, out)

// ---------------------------------------------------------------------------
// Palette emission (status dots, folder identity colors)
// ---------------------------------------------------------------------------

const paletteRGBA = Object.fromEntries(
  Object.entries(TAILWIND).map(([name, value]) => {
    const rgba = parseOklch(value)
    if (!rgba) throw new Error(`could not parse the Tailwind value for ${name}`)
    return [name, rgba]
  })
)

const swiftColor = (name) => {
  const c = paletteRGBA[name]
  return `Color(.sRGB, red: ${f(c.r)}, green: ${f(c.g)}, blue: ${f(c.b)}, opacity: 1)`
}

let palette = `// Generated by scripts/gen-web-tokens.mjs — DO NOT EDIT BY HAND.
//
// The Tailwind ramp colors the web client uses directly, rather than through a
// theme token: conversation status dots and the 16 folder identity colors. They
// are deliberately *not* theme-driven — a folder keeps its color and a status
// keeps its meaning under every preset, on the web and here.

import SwiftUI

enum WebPalette {
${Object.keys(TAILWIND)
  .map((name) => `    /// Tailwind \`${name}\`\n    static let ${camel(name)} = ${swiftColor(name)} // ${hex(paletteRGBA[name])}`)
  .join("\n")}
}

/// \`STATUS_COLORS\` from src/lib/types.ts. The web uses one value per status in
/// both color schemes, so these carry no light/dark pair.
enum WebStatusPalette {
${Object.entries(STATUS_COLORS)
  .map(
    ([status, color]) =>
      `    /// \`bg-${color}\`\n    static let ${status} = WebPalette.${camel(color)}`
  )
  .join("\n")}
    /// The web's fallback for an unknown status (\`bg-gray-400 dark:bg-gray-500\`).
    static let unknown = Color(light: WebPalette.gray400, dark: WebPalette.gray500)
}

/// \`folderBadgeColor\` / \`folderBadgeLabel\` from src/lib/folder-badge.ts: a
/// folder's identity color is its id modulo the ramp, so the same folder gets
/// the same color in both clients.
enum WebFolderPalette {
    static let colors: [Color] = [
${FOLDER_COLORS.map((name) => `        WebPalette.${camel(name)}, // ${name}`).join("\n")}
    ]

    static func color(forFolderID id: Int) -> Color {
        colors[abs(id) % colors.count]
    }

    /// The badge's single-character label: the name's first letter or digit,
    /// uppercased; \`?\` when there is neither.
    static func label(for name: String) -> String {
        for character in name {
            if character.isLetter || character.isNumber {
                return character.uppercased()
            }
        }
        return name.isEmpty ? "?" : String(name.prefix(1)).uppercased()
    }
}
`

writeFileSync(PALETTE_OUT, palette)

console.log(
  `wrote ${OUT}\n  ${THEMES.length} presets × 2 schemes × ${TOKENS.length} tokens = ${
    THEMES.length * 2 * TOKENS.length
  } values\n  source: ${SOURCE}\n` +
    `wrote ${PALETTE_OUT}\n  ${Object.keys(TAILWIND).length} Tailwind ramp colors, ` +
    `${FOLDER_COLORS.length} folder colors, ${Object.keys(STATUS_COLORS).length} status colors`
)
