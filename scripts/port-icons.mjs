#!/usr/bin/env node
// One-shot codemod for the web-style port: rewrites standalone SF Symbol images
// to the bundled Lucide glyphs.
//
//   node scripts/port-icons.mjs [--dry]
//
// Scope is deliberately narrow — only `Image(systemName:)` whose size is an
// explicit `.font(WebTheme.sans(N…))`, either chained on the same line or on the
// line below:
//
//     Image(systemName: "chevron.right")        LucideIcon(sf: "chevron.right", size: 12)
//         .font(WebTheme.sans(12, .semibold))
//
// Skipped on purpose, and listed at the end for a human:
//
//   * `.resizable()` / `.scaledToFit()` — sized by an enclosing frame, which
//     LucideIcon expresses differently (it takes a point size).
//   * `.imageScale`, `.symbolVariants`, `.symbolRenderingMode`, `.symbolEffect`,
//     `.renderingMode` — SF Symbol APIs with no icon-font equivalent.
//   * `Label(…, systemImage:)` — a structural rewrite, and in a context menu or
//     a toolbar the native SF Symbol is the *right* glyph: those are system
//     surfaces, not app canvas. Migrate them per screen, deliberately.

import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs"
import { join, relative, resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const ROOT = join(REPO, "CodegiOS")
const DRY = process.argv.includes("--dry")

const mapping = JSON.parse(
  readFileSync(join(REPO, "scripts/sf-to-lucide.json"), "utf8")
)

/** Modifiers that mean "this is an SF Symbol, leave it alone". */
const SF_ONLY =
  /\.(resizable|scaledToFit|imageScale|symbolVariants|symbolRenderingMode|symbolEffect|renderingMode)\b/

const IMAGE = /Image\(systemName:\s*"([^"]+)"\)/
const SIZED_FONT = /\.font\(WebTheme\.sans\(([^,)]+)(?:,\s*\.[a-zA-Z]+)?\)\)/

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry)
    if (statSync(path).isDirectory()) return swiftFiles(path)
    return path.endsWith(".swift") ? [path] : []
  })
}

let changedLines = 0
let changedFiles = 0
const skipped = []

for (const file of swiftFiles(ROOT)) {
  const lines = readFileSync(file, "utf8").split("\n")
  const out = []
  let touched = false

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const image = line.match(IMAGE)
    if (!image) {
      out.push(line)
      continue
    }

    const symbol = image[1]
    const lucide = mapping.map[symbol]
    const next = lines[i + 1] ?? ""

    const reason = !(symbol in mapping.map)
      ? "no mapping"
      : lucide === null
        ? "deliberately unmapped (use WebStatusDot)"
        : SF_ONLY.test(line) || SF_ONLY.test(next)
          ? "SF-only modifiers"
          : null

    if (reason) {
      skipped.push(`${relative(REPO, file)}:${i + 1}: ${symbol} — ${reason}`)
      out.push(line)
      continue
    }

    // Same line: Image(...).font(WebTheme.sans(N…))
    const inlineFont = line.match(SIZED_FONT)
    if (inlineFont) {
      const replaced = line
        .replace(IMAGE, `LucideIcon(sf: "${symbol}", size: ${inlineFont[1].trim()})`)
        .replace(SIZED_FONT, "")
      console.log(`${relative(REPO, file)}:${i + 1}\n  - ${line.trim()}\n  + ${replaced.trim()}`)
      out.push(replaced)
      changedLines++
      touched = true
      continue
    }

    // Next line carries the size.
    const nextFont = next.match(SIZED_FONT)
    if (nextFont && next.trim().startsWith(".font(") && next.trim().endsWith(")")) {
      const replaced = line.replace(
        IMAGE,
        `LucideIcon(sf: "${symbol}", size: ${nextFont[1].trim()})`
      )
      console.log(
        `${relative(REPO, file)}:${i + 1}\n  - ${line.trim()}\n  - ${next.trim()}\n  + ${replaced.trim()}`
      )
      out.push(replaced)
      changedLines++
      touched = true
      i++ // consume the font line
      continue
    }

    skipped.push(`${relative(REPO, file)}:${i + 1}: ${symbol} — no explicit size`)
    out.push(line)
  }

  if (touched) {
    changedFiles++
    if (!DRY) writeFileSync(file, out.join("\n"))
  }
}

console.log(`\n${DRY ? "[dry run] " : ""}${changedLines} icons in ${changedFiles} files`)
if (skipped.length) {
  const bySymbol = skipped.length
  console.log(`\nLeft as SF Symbols (${bySymbol}):\n  ${skipped.join("\n  ")}`)
}
