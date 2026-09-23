# Changelog

All notable changes to Codeg for iOS are recorded here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Add changes under `## [Unreleased]` as you work. When you cut a release,
`scripts/release.sh` moves that section under a new version heading and reuses
the text as the git tag message and the GitHub Release notes.

## [Unreleased]

### Fixed

- Long press works again inside the sidebar / aux / terminal drawers (rename,
  pin, delete a conversation; a folder's new conversation). The long-press
  guard now applies only outside the drawers — the transcript, where a long
  press means "select text".

## [0.0.5] — 2026-09-21

### Changed

- The Dynamic Island's ring is a clock: one lap is ten minutes of the turn's
  wall-clock time (it was a bar against a two-hour window, which read as a
  progress percentage that meant nothing). The subtitle now leads with the
  elapsed time — "4 min · Editing foo.swift" — so the expanded view and the
  lock screen show the figure before a long phase gets truncated.
- Focusing the composer no longer zooms the page in. The keyboard still
  scrolls the field into view; only WebKit's under-16px focus zoom is off.

## [0.0.4] — 2026-09-21

### Changed

- Tapping a notification (task completed / failed, permission, question, plan)
  opens the conversation it is about, switching servers first if needed.
  Action buttons on notifications still answer without opening the app.
- The Dynamic Island's phase line says what the agent is doing in plain
  words — Thinking / Writing / Editing <file> / Running <command> / Reading /
  Searching / Browsing — and the three waits are told apart: Needs your
  permission / Has a question for you / Plan awaiting your review. With several
  tasks running, one that needs you takes the first line.
- Long-press guards moved to `window` so they bracket React's own dispatch;
  the page's context menus no longer open from a long press on touch.

## [0.0.3] — 2026-09-21

### Changed

- Coming back from the background no longer loses the text the agent streamed
  meanwhile. The page's event socket dies with the radio but the web client
  only hears about it late; the app now closes that socket on every return
  to the foreground so the page reconnects (and re-syncs) at once.
- A running turn is picked up within a round-trip: the app now listens to the
  server's global `conversation://changed` side-channel over a WebSocket
  (`ServerEventHub`) and attaches as soon as a session flips to running; the
  25-second poll stays as the safety net.
- The continued-processing task now reports real (wall-clock) progress every
  20 seconds. It reported none before, which is grounds for the system to
  expire it — the likely reason the Dynamic Island kept dropping mid-turn.
- A running turn's event socket retries for up to ten minutes (backoff capped
  at 15s) instead of giving up after about thirty seconds.
- The Dynamic Island is titled after the conversation.
- The page's floating selection toolbar (copy / quote / ask) is hidden on
  touch; it sat on top of iOS's own selection callout and the two fought over
  the selection. Touch keeps the system callout; mouse and trackpad keep the
  page's toolbar.
- Releases are cut by pushing a `v<version>` tag. A push to `main` only builds.

## [0.0.2] — 2026-09-21

### Changed

- The native title bar is gone. The server switcher is now a small pill laid
  over the empty middle of the web client's own mobile title bar; Reload moved
  into its menu.
- A long press no longer opens the page's context menus on touch (they were
  built for right-click and stole the composer's focus on a phone). Mouse and
  trackpad keep them. Link/image long-press previews are off too.

## [0.0.1] — 2026-09-21

Version numbering starts over: this is a new app (`app.codeg.ios.web`), not a
build of the native codeg-ios client the earlier `1.0.1` entries describe.


### Changed

- **New app identity**: bundle id `app.codeg.ios.web`, display name "Codeg
  Web", URL scheme `codegweb://`, continued-processing task prefix
  `app.codeg.ios.web.continued.agent`. Installs beside the original codeg-ios
  app; being a new app, saved servers must be added again.
- **The app now shows the codeg web client** (`/workspace` from the selected
  server, in a `WKWebView`) instead of native SwiftUI screens. The token is
  injected before the page loads; same-origin navigation stays in-app,
  everything else opens in Safari; a rejected token surfaces as a native
  "edit the server" state rather than the page's login form.
- Live Activity, continued processing and background notifications are now
  driven by `RunningTurnWatcher`, a native attach to each running session's ACP
  connection, so they work regardless of which client started the turn.
- Live Activity taps and `codegweb://conversation/<id>` links open the
  conversation through the web client's own deep-link query.

### Added

- iOS 26 continued-processing support for user-started live agent streams.
- Actionable background notifications for permission requests, agent questions,
  and plan approvals, including a second confirmation for Always Allow.
- GitHub Actions packaging for a verified unsigned device IPA.
- `docs/background-agent-ux.md` with the accepted background/recovery UX design.

### Changed

- Apple signing now uses an ignored local configuration instead of a committed
  development team identifier.
- Live event sockets transparently reconnect and re-attach with `since_seq`, so
  ordinary Wi-Fi/5G/VPN changes and short background interruptions no longer
  have to become visible chat reconnect state.
- Network restoration accelerates an already-pending reconnect without tearing
  down a still-healthy socket merely because the network path changed.
- iOS background coordination now starts only after the WebSocket server has
  completed the initial upgrade and the client begins its attach handshake.
- Continued-processing Live Activity updates are now state-based and minute-
  granularity, showing elapsed time instead of continuously advancing a fake
  completion percentage.
- Tapping the system Live Activity now restores the owning server/session using
  lightweight persisted routing hints; ordinary app foregrounding remains unchanged.
- Native iOS WebSocket upgrades now authenticate with the same
  `Authorization: Bearer <token>` header used by normal Codeg API requests and
  advertise only the `codeg-events` application subprotocol. The browser-only
  `codeg-token.*` authentication subprotocol is no longer used by iOS.
- WebSocket tokens are trimmed before the upgrade request, matching the web
  client's normalization behavior.

### Fixed

- Returning from another app no longer needs to treat the foreground transition
  itself as a connection failure.
- Pending interactive requests are restored from an authoritative re-attach
  snapshot and can be surfaced as background actions after a transient drop.
- Restored the upstream-equivalent initial WebSocket handshake path after the
  first tapaixx background build could fail before attach with iOS reporting
  "the server returned an invalid response". Handshake failures now include the
  HTTP status code when URLSession exposes it, to distinguish auth/route/proxy
  failures from transport recovery failures.
- Fixed WebSocket HTTP 403 failures behind CDNs/WAFs that require the normal
  bearer token during the HTTP Upgrade request rather than accepting an encoded
  token hidden in `Sec-WebSocket-Protocol`.

## [1.0.1] - 2026-07-07

### Added

- **New agent types** — CodeBuddy, Kimi Code, and Pi.
- One-command release automation: `scripts/release.sh` bumps the version, files
  the release notes, tags, pushes, and creates a GitHub Release (with an
  optional `--archive` App Store Connect upload leg).
- This `CHANGELOG.md` as the home for version notes.

### Changed

- The app version is now single-sourced from `MARKETING_VERSION` /
  `CURRENT_PROJECT_VERSION` in `project.yml`.

### Fixed

- Streaming no longer rebuilds the entire transcript on every token, keeping
  long sessions smooth.
- The pending approval card is restored after a mid-turn stream reconnect.
- `Info.plist` no longer hardcodes `CFBundleShortVersionString`, which had
  silently overridden `MARKETING_VERSION` so version bumps didn't take effect.

## [1.0.0] - 2026-06-07

### Added

- Initial Codeg for iOS release.
