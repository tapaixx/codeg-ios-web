# Codeg for iOS — web client shell

An iPhone + iPad app for the [codeg](https://github.com/xintaofei/codeg)
multi-agent coding server. **The screens are the codeg web client's** — the
app loads `http(s)://your-server/workspace` in a `WKWebView`, the same page a
phone browser shows, so what you see is exactly the web client at whatever
version your server runs. Nothing is drawn over it.

What the app adds is what a browser tab cannot do:

- **Servers and tokens** — several codeg servers, each with its token in the
  Keychain. The token is handed to the page before its own scripts run (the web
  client reads `localStorage["codeg_token"]`), so `/workspace` never detours
  through `/login`. The title bar is the server switcher.
- **Live Activity / Dynamic Island** for an in-flight agent turn, with iOS 26
  continued processing so the turn keeps streaming after you leave the app.
- **Actionable notifications** for permission requests, agent questions and plan
  approvals while the app is in the background — answered from the notification
  without opening the app.
- **Deep links** — a Live Activity tap or a `codegweb://conversation/<id>` link
  lands the page on that conversation via the web's own
  `/workspace?folderId&conversationId&agent` entry.

How the background pieces work without the native transcript screen:
`RunningTurnWatcher` polls the server's running sessions and opens a read-only
native attach (`EventStream`) to each one's ACP connection; the existing
`BackgroundAgentCoordinator` then does what it always did. It is blind to what
the page is showing on purpose — a session started from the desktop gets the
same treatment as one started on the phone.

This is a fork of [codeg-ios](https://github.com/tapaixx/codeg-ios). The
native SwiftUI screens it inherited (and the design-system port that restyled
them, see [`docs/web-style-port.md`](docs/web-style-port.md)) are still in the
tree but no longer reachable; they will be removed once the shell has been
verified on devices.

## Requirements

- Xcode 26 / iOS 26 SDK
- [XcodeGen](https://github.com/yonyz/XcodeGen) (`brew install xcodegen`) — the
  Xcode project is generated from `project.yml`

## Build & run

Simulator builds do not require an Apple Developer account:

```bash
xcodegen generate            # regenerate CodegiOS.xcodeproj from project.yml
open CodegiOS.xcodeproj
```

For a physical device or archive, create the ignored local signing override
before generating the project:

```bash
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
# Edit Signing.local.xcconfig and replace YOUR_TEAM_ID.
xcodegen generate
```

Or from the command line (simulator):

```bash
xcodebuild -project CodegiOS.xcodeproj -scheme CodegiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -skipMacroValidation build
```

> Run the app in Xcode with your development team selected so it is code-signed —
> the Keychain (used for tokens) requires the app's `application-identifier`
> entitlement. Unsigned CLI/simulator builds transparently fall back to a
> UserDefaults token store (simulator only) so the app stays usable.

## Releasing

Cutting a release is one command:

```bash
scripts/release.sh patch          # 1.0.0 -> 1.0.1 (build auto-increments)
scripts/release.sh minor          # 1.0.0 -> 1.1.0
scripts/release.sh 1.2.0          # set an explicit version
```

It bumps `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` (the
single source of truth for the version), regenerates the project, commits, tags
`vX.Y.Z`, pushes, and creates a GitHub Release.

**Version notes** live in [`CHANGELOG.md`](CHANGELOG.md): jot changes under
`## [Unreleased]` as you work. On release, that section is promoted to a
`## [X.Y.Z]` heading and reused verbatim as the git tag message and the GitHub
Release notes. Override the notes ad hoc with `--notes "…"`; if both are empty
the script opens `$EDITOR`.

Useful flags:

```bash
scripts/release.sh patch --dry-run   # print every step, change nothing
scripts/release.sh patch --yes       # skip the confirmation prompt
scripts/release.sh minor --archive   # also archive + upload to App Store Connect
```

`--archive` runs `xcodebuild archive`/`-exportArchive` (via
[`scripts/ExportOptions.plist`](scripts/ExportOptions.plist)) and, when an App
Store Connect API key is present, uploads the `.ipa`. This happens **before** the
tag and GitHub Release are published, so a signing/export/upload failure aborts
with nothing committed or pushed (the script prints how to discard the bump).
Provide the key via environment variables:

```bash
export CODEG_DEVELOPMENT_TEAM=XXXXXXXXXX # optional if local signing config exists
export ASC_KEY_ID=XXXXXXXXXX          # the App Store Connect API Key ID
export ASC_ISSUER_ID=xxxxxxxx-xxxx-…  # the Issuer ID
export ASC_KEY_PATH=~/AuthKey_XXXXXXXXXX.p8
```

Without them the archive step still exports a local `.ipa` (upload it via
Transporter.app). `altool` uploads only the binary — the App Store "What's New"
text is saved to `build/release-notes-vX.Y.Z.txt` for you to paste into App
Store Connect. To automate that text too, graduate `--archive` to Fastlane
[`deliver`](https://docs.fastlane.tools/actions/deliver/).

## Connecting to a server

1. Start a codeg server (`CODEG_PORT` default `3080`). It prints a `CODEG_TOKEN`
   to stderr on startup.
2. In the app, tap **+**, enter a name, the server URL (e.g. `http://192.168.1.10:3080`),
   and the token. Use **Test Connection** to validate, then **Save**.

## Architecture

```
CodegiOS/
  App/            App entry, AppModel (selection state), RootView (NavigationSplitView)
  Models/         Codable wire models (AgentType, Conversation, Message, AcpEvent)
  Networking/     CodegClient (HTTP), EventStream (WebSocket), JSON coding, errors
  Persistence/    ServerProfile, Keychain, ServerStore (Observable)
  DesignSystem/   Liquid Glass components, theme tokens, badges, state views
  Features/       Servers, Sessions, SessionDetail (each: View + @Observable model)
```

Key contract details handled by the networking layer:

- **Mixed JSON casing** — requests are camelCase, responses are snake_case
  (`JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`; encoder keeps keys).
- **Auth** — HTTP `Authorization: Bearer <token>`; WebSocket auth via the
  `codeg-token.<base64url-no-pad>` subprotocol.
- **Streaming** — `acp_connect` → WS attach (awaiting snapshot confirmation) →
  `acp_prompt` → consume `content_delta` / `tool_call` / `turn_complete` events.

The three-column `NavigationSplitView` (servers | sessions | detail) collapses to
a navigation stack on iPhone.

## License

Codeg for iOS is licensed under the [Apache License 2.0](LICENSE). Third-party
license notices are collected in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Product and service names used by the app identify compatible integrations.
Their trademarks belong to their respective owners; no endorsement or
affiliation is implied.
