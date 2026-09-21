#!/usr/bin/env node
// One-shot codemod for the web-style port: rewrites the remaining Liquid Glass
// surfaces and button styles in the feature code to their web equivalents.
//
//   node scripts/port-glass-surfaces.mjs [--dry]
//
// The design-system files were ported by hand; this handles the call sites that
// reach for the system glass APIs directly. Every rule is printed with its
// before/after line so the sweep can be reviewed rather than trusted. Kept in
// the repo (rather than run and deleted) because the mapping it encodes is the
// answer to "what replaced glass here?" — see docs/web-style-port.md.

import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs"
import { join, relative, resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const ROOT = join(REPO, "CodegiOS")
const DRY = process.argv.includes("--dry")

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry)
    if (statSync(path).isDirectory()) return swiftFiles(path)
    return path.endsWith(".swift") ? [path] : []
  })
}

/**
 * Line-level rules. `match` gets the line and its successor (some glass surfaces
 * are followed by a hairline that the replacement already draws).
 */
const RULES = [
  {
    name: "glass card → bg-card + existing hairline",
    test: (line, next) =>
      /\.glassEffect\(\.regular, in: RoundedRectangle\(cornerRadius: (.+?), style: \.continuous\)\)/.test(
        line
      ) && /\.hairlineBorder\(/.test(next ?? ""),
    apply: (line) =>
      line.replace(
        /\.glassEffect\(\.regular, in: (RoundedRectangle\(cornerRadius: .+?, style: \.continuous\))\)/,
        ".background(WebTheme.card, in: $1)"
      ),
  },
  {
    name: "glass card → webCardSurface",
    test: (line) =>
      /\.glassEffect\(\.regular, in: RoundedRectangle\(cornerRadius: (.+?), style: \.continuous\)\)/.test(
        line
      ),
    apply: (line) =>
      line.replace(
        /\.glassEffect\(\.regular, in: RoundedRectangle\(cornerRadius: (.+?), style: \.continuous\)\)/,
        ".webCardSurface(cornerRadius: $1)"
      ),
  },
  {
    name: "glass disc → popover surface (drops the now-doubled hairline)",
    test: (line) => /\.glassEffect\(\.regular, in: Circle\(\)\)/.test(line),
    apply: (line) =>
      line.replace(/\.glassEffect\(\.regular, in: Circle\(\)\)/, ".webPopoverSurface(Circle())"),
    dropNextIf: /^\s*\.hairlineBorder\(/,
  },
  {
    name: "tinted glass capsule (toast) → popover surface",
    test: (line) =>
      /\.glassEffect\(\.regular\.tint\(Theme\.accent(Dim|\.opacity\([\d.]+\))\), in: Capsule\(\)\)/.test(
        line
      ),
    apply: (line) =>
      line.replace(
        /\.glassEffect\(\.regular\.tint\(Theme\.accent(?:Dim|\.opacity\([\d.]+\))\), in: Capsule\(\)\)/,
        ".webPopoverSurface(Capsule(style: .continuous))"
      ),
  },
  {
    name: "tinted glass panel → bg-muted",
    test: (line) =>
      /\.glassEffect\(\.regular\.tint\(Theme\.accent(?:Dim|\.opacity\([\d.]+\))\), in: (RoundedRectangle\(.+?\))\)/.test(
        line
      ),
    apply: (line) =>
      line.replace(
        /\.glassEffect\(\.regular\.tint\(Theme\.accent(?:Dim|\.opacity\([\d.]+\))\), in: (RoundedRectangle\(.+?\))\)/,
        ".background(WebTheme.muted, in: $1)"
      ),
  },
  {
    name: "prominent glass button → web primary",
    test: (line) => /\.buttonStyle\(\.glassProminent\)/.test(line),
    apply: (line) =>
      line.replace(/\.buttonStyle\(\.glassProminent\)/, ".buttonStyle(.web(.primary))"),
  },
  {
    name: "glass button → web outline",
    test: (line) => /\.buttonStyle\(\.glass\)/.test(line),
    apply: (line) => line.replace(/\.buttonStyle\(\.glass\)/, ".buttonStyle(.web(.outline))"),
  },
]

let changedFiles = 0
let changedLines = 0
const unhandled = []

for (const file of swiftFiles(ROOT)) {
  const source = readFileSync(file, "utf8")
  const lines = source.split("\n")
  const out = []
  let touched = false

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    const rule = RULES.find((r) => r.test(line, lines[i + 1]))
    if (!rule) {
      if (/\.glassEffect\(|buttonStyle\(\.glass/.test(line) && !line.trim().startsWith("//")) {
        unhandled.push(`${relative(REPO, file)}:${i + 1}: ${line.trim()}`)
      }
      out.push(line)
      continue
    }
    const replaced = rule.apply(line)
    console.log(
      `${relative(REPO, file)}:${i + 1}  [${rule.name}]\n  - ${line.trim()}\n  + ${replaced.trim()}`
    )
    out.push(replaced)
    touched = true
    changedLines++
    if (rule.dropNextIf && rule.dropNextIf.test(lines[i + 1] ?? "")) {
      console.log(`  ✕ ${lines[i + 1].trim()}`)
      i++
    }
  }

  if (touched && !DRY) {
    writeFileSync(file, out.join("\n"))
    changedFiles++
  } else if (touched) {
    changedFiles++
  }
}

console.log(
  `\n${DRY ? "[dry run] " : ""}${changedLines} lines in ${changedFiles} files`
)
if (unhandled.length) {
  console.log(`\nStill using a glass API (needs a human):\n  ${unhandled.join("\n  ")}`)
}
