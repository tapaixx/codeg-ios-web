#!/usr/bin/env node
// One-shot codemod for the web-style port: rewrites SwiftUI's system fonts to
// the web client's type scale in Inter / JetBrains Mono.
//
//   node scripts/port-fonts.mjs [--dry]
//
// Without this the app is half Inter (everything drawn by the design system)
// and half San Francisco (everything a screen styled itself), which reads worse
// than either alone. Every rewrite is printed; anything the rules don't
// recognize is listed at the end instead of being guessed at.
//
// The size mapping is not 1:1 with iOS's point sizes — that is the point. iOS's
// text styles run large (body 17pt, subheadline 15pt); the web client's UI is
// `text-sm` (14) for rows and controls and `text-xs` (12) for meta. Each style
// lands on the web step that plays its role, so the port changes *density*, not
// just the typeface.

import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs"
import { join, relative, resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const ROOT = join(REPO, "CodegiOS")
const DRY = process.argv.includes("--dry")

/** iOS text style → [web point size, inherent weight]. */
const STYLE_MAP = {
  largeTitle: [24, "bold"],
  title: [20, "bold"],
  title2: [18, "semibold"],
  title3: [16, "semibold"],
  headline: [14, "semibold"],
  body: [14, "regular"],
  callout: [14, "regular"],
  subheadline: [14, "regular"],
  footnote: [12, "regular"],
  caption: [12, "regular"],
  caption2: [11, "regular"],
}

/** SwiftUI weight → one of the four bundled faces. */
const WEIGHT_MAP = {
  ultraLight: "regular",
  thin: "regular",
  light: "regular",
  regular: "regular",
  medium: "medium",
  semibold: "semibold",
  bold: "bold",
  heavy: "bold",
  black: "bold",
}

const call = (fn, size, weight) =>
  weight === "regular"
    ? `WebTheme.${fn}(${size})`
    : `WebTheme.${fn}(${size}, .${weight})`

/**
 * Rewrites one `.font(…)` argument, or returns null when the form isn't one the
 * port understands (already ported, `.mono(…)`, a `Theme.Typography` token, a
 * variable — all of which must be left alone).
 */
function rewriteFontArgument(arg) {
  const trimmed = arg.trim()

  // Already ported, or an app token that resolves to the right thing already.
  if (/^(WebTheme|Theme\.Typography|\.mono\(|\.custom\()/.test(trimmed)) return null

  // .system(size: N[, weight: .W][, design: .monospaced]). The size may be an
  // expression (`d * 0.42`) as long as it has no commas or parentheses of its
  // own, which would break this line-level parse.
  const system = trimmed.match(
    /^\.system\(size:\s*([^,()]+?)\s*(?:,\s*weight:\s*\.([a-zA-Z]+)\s*)?(?:,\s*design:\s*\.([a-zA-Z]+)\s*)?\)$/
  )
  if (system) {
    const [, size, weight, design] = system
    const face = design === "monospaced" ? "mono" : "sans"
    return call(face, size, WEIGHT_MAP[weight ?? "regular"] ?? "regular")
  }

  // .style.monospaced()[.weight(.W)] — a text style asking for the code face,
  // which is JetBrains Mono here, at that style's web size.
  const monospaced = trimmed.match(
    /^\.([a-zA-Z0-9]+)\.monospaced\(\)(?:\.weight\(\.([a-zA-Z]+)\))?$/
  )
  if (monospaced) {
    const [, name, weight] = monospaced
    const mapped = STYLE_MAP[name]
    if (!mapped) return null
    return call("mono", mapped[0], WEIGHT_MAP[weight ?? "regular"] ?? "regular")
  }

  // .style[.weight(.W)][.monospacedDigit()], in either order
  const style = trimmed.match(
    /^\.([a-zA-Z0-9]+)(?:\.weight\(\.([a-zA-Z]+)\))?(\.monospacedDigit\(\))?(?:\.weight\(\.([a-zA-Z]+)\))?$/
  )
  if (style) {
    const [, name, weightBefore, digits, weightAfter] = style
    const mapped = STYLE_MAP[name]
    if (!mapped) return null
    const [size, inherent] = mapped
    const weight = weightBefore ?? weightAfter
    const face = WEIGHT_MAP[weight ?? inherent] ?? inherent
    return call("sans", size, face) + (digits ?? "")
  }

  return null
}

/** Finds `.font(` calls and returns [start, end) of the balanced argument. */
function* fontCalls(line) {
  const needle = ".font("
  let from = 0
  while (true) {
    const index = line.indexOf(needle, from)
    if (index === -1) return
    const start = index + needle.length
    let depth = 1
    let i = start
    let inString = false
    for (; i < line.length; i++) {
      const c = line[i]
      if (c === '"' && line[i - 1] !== "\\") inString = !inString
      if (inString) continue
      if (c === "(") depth++
      else if (c === ")") {
        depth--
        if (depth === 0) break
      }
    }
    if (depth !== 0) return // unbalanced on this line — leave it alone
    yield { start, end: i }
    from = i + 1
  }
}

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
  // The design system was ported by hand and already speaks in web tokens.
  if (file.includes("/DesignSystem/")) continue

  const lines = readFileSync(file, "utf8").split("\n")
  let touched = false

  for (let index = 0; index < lines.length; index++) {
    const original = lines[index]
    if (!original.includes(".font(")) continue

    let line = original
    // Right to left, so earlier offsets stay valid as the line grows.
    const calls = [...fontCalls(line)].reverse()
    for (const { start, end } of calls) {
      const arg = line.slice(start, end)
      const replacement = rewriteFontArgument(arg)
      if (replacement === null) {
        if (!/^(WebTheme|Theme\.Typography|\.mono\(|\.custom\()/.test(arg.trim())) {
          skipped.push(`${relative(REPO, file)}:${index + 1}: .font(${arg})`)
        }
        continue
      }
      line = line.slice(0, start) + replacement + line.slice(end)
    }

    if (line !== original) {
      console.log(`${relative(REPO, file)}:${index + 1}\n  - ${original.trim()}\n  + ${line.trim()}`)
      lines[index] = line
      changedLines++
      touched = true
    }
  }

  if (touched) {
    changedFiles++
    if (!DRY) writeFileSync(file, lines.join("\n"))
  }
}

console.log(`\n${DRY ? "[dry run] " : ""}${changedLines} lines in ${changedFiles} files`)
if (skipped.length) {
  console.log(`\nLeft alone (unrecognized form — check by hand):\n  ${skipped.join("\n  ")}`)
}
