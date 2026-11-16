# Jutsu for iPhone — architecture

The app is a native client for Higgsfield with no server of its own. Its Swift packages started as a copy of the Mac
app [Jutsu Studio](https://github.com/jutsuhq/jutsu-studio) (MIT, see [`Packages/UPSTREAM.md`](../Packages/UPSTREAM.md))
and are maintained here. Rules live in the packages and are tested there; the app target holds views and system glue.

## Baseline

| Decision | Choice |
|---|---|
| Platform | iOS 18.0+, iPhone and iPad from one target. Liquid Glass, tab bar minimizing and `BGContinuedProcessingTask` are used from iOS 26 with fallbacks in `App/DesignSystem/LiquidGlass.swift` and `App/System/BackgroundWork.swift` |
| Language | Swift 6 language mode, strict concurrency |
| App target isolation | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` |
| Package isolation | Nonisolated by default, explicit actors (`JobEngine`, `SlotLimiter`, `TokenProvider`, the SwiftData stores) |
| UI | SwiftUI; UIKit only through representables where SwiftUI has gaps |
| State | `@Observable` models from `Presentation`, owned by one composition root |
| Storage | SwiftData for jobs and the Library catalog, files in the app container, Keychain for secrets |
| Third-party code | None; system frameworks only |
| Tests | Swift Testing; the portable modules also run on Linux |

## Layout

```
project.yml          XcodeGen spec: app, widget and share extension targets
App/                 iOS app target
  App/               JutsuApp (@main), AppEnvironment, navigation, connection
  DesignSystem/      theme, glass styles and their pre-iOS 26 fallbacks, shared view pieces
  Onboarding/  Create/  Queue/  Library/  Account/
  System/            background work, downloads, notifications, Live Activity, Photos export, App Intents
  Resources/         assets, fonts, string catalogs, privacy manifest
Widgets/             Live Activity, Dynamic Island, Home and Lock Screen widgets
Share/               share extension: copies a shared video or image into the app group inbox
Shared/              code compiled into more than one target (widget snapshot, shared inbox)
Packages/
  HiggsfieldKit/     HiggsfieldCore, HiggsfieldAPI (API key), HiggsfieldMCP (account over MCP and OAuth)
  JutsuKit/          JutsuCore, HiggsfieldProviders, JobEngine, Presentation, Persistence, MediaKit, Secrets
scripts/             lint, format, tests, architecture and log-privacy checks, store asset generators
```

`JutsuCore` imports only Foundation and `HiggsfieldKit` knows nothing of the app. `scripts/check-architecture.sh`
keeps the per-module framework allow-list; SwiftPM enforces module-to-module dependencies. Both `Package.swift` files
also declare macOS so `swift test` runs on a Mac without a simulator.

## Composition root

`AppEnvironment` is one `@Observable` object created in `JutsuApp`. It owns the `ModelContainer`, the `JobEngine`,
the `ConnectionStore` and the providers built for the active connection.

| Type | File | Owns |
|---|---|---|
| `AppEnvironment` | `App/App/AppEnvironment.swift` | the store, engine, connection and provider; `enqueue`, `perform`, `use(_:)` |
| `AppEnvironment+Capabilities` | `App/App/` | every `provider as? any X` lookup, in one place |
| `AppEnvironment+Lifecycle` | `App/App/` | background, foreground, background refresh, the widget snapshot |
| `AppEnvironment+Media` | `App/App/` | downloads from Higgsfield: inputs cached in Application Support, results saved to Documents/Images |
| `NavigationModel` | `App/App/` | the tab, and one-shot routes consumed by the screen they are for |
| `CreateScreenModel` | `App/Create/` | the video form, prices, today's spend, submit with the cap check, the draft |
| `LibraryModel` + `LibraryMarks` | `App/Library/` | finished takes from the store, variants; keep, reject, star, scores |
| `SharedInboxImporter` | `App/System/` | files from the share extension, removed from the app group once read |

Logging goes through `Logger.jutsu(_:)`; `scripts/check-log-privacy.sh` fails on a value logged as public that isn't plainly safe.

## Background execution

The engine saves every job transition before acting on it and resumes active jobs from the store on start, so a
suspended or killed process loses nothing.

- **Downloads** go through `BackgroundDownloader`, the engine's `Downloader` on a background `URLSession`. A relaunch
  finds the finished file.
- **Prepare, upload and submit** of jobs queued with Generate run in a `BGContinuedProcessingTask` on iOS 26 and later
  (`BackgroundWork`), with the system's progress UI.
- **Polling** in the background is a `BGAppRefreshTask` that starts the engine for a short, bounded check.
- Leaving the app otherwise stops the engine, letting submits in flight finish within a few seconds; returning starts
  it again.

One idempotency key per job is reused on every resubmit, and an account submit that may have reached the server is
never silently resent (`outcomeUnknown`).

## Account sign-in

OAuth 2.1 with PKCE against Higgsfield's MCP server: discovery, a Client ID Metadata Document, PKCE S256, `resource`,
`iss` check and token refresh in `HiggsfieldMCP`. The browser step is `WebAuthenticationPresenter`, an
`ASWebAuthenticationSession` with an HTTPS callback on the auth domain. That domain serves the client metadata and the
`apple-app-site-association` file for `applinks` and `webcredentials`.

Tokens go through `TokenProvider` (refresh ahead of expiry, single flight, one retry after 401). The Keychain item is
readable after first unlock so background tasks can use it, is not shared with extensions and never synchronizes.
The app has no sign-up, purchase or link to either (App Review 3.1.3(f)).

## Media and files

- Inputs come from `PhotosPicker`, `fileImporter` or the share extension and are copied into the container; no
  bookmarks are kept.
- `MediaPreparer` trims and transcodes before upload. Heavy processing (upscale, reframe, background removal, voice)
  runs on Higgsfield, not on the device.
- Results land in `Documents/Videos` and `Documents/Images`, visible in the Files app. Save to Photos asks for
  add-only access.
- Export for Editing writes ProRes 422 or H.264 with a JSON sidecar.
- App data lives in `Library/Application Support/Jutsu/`; thumbnails and diagnostics in `Library/Caches`.
- Deleting a take removes its file; Reject only hides it.

## System surfaces

- **Live Activity:** one per batch, updated whenever the app runs, ended on the last result. No push updates.
- **Notifications:** local only, category `TAKE_READY`, posted when the engine learns an outcome.
- **Widgets:** read a snapshot the app writes into the app group after engine changes.
- **Share extension:** links nothing from JutsuKit and holds no credentials.
- **App Intents:** Shortcuts and Siri open the app.

## Security and privacy

- No backend and no analytics. The app talks only to Higgsfield's API, its MCP and OAuth servers, and the presigned
  storage hosts they return.
- `os.Logger` with `privacy: .private` for tokens, keys and signed URLs.
- The privacy manifest declares no tracking and the required-reason APIs actually used.
- `scripts/check-secrets.sh` runs gitleaks over the full history.

## Testing and CI

CI (`.github/workflows/ci.yml`) runs lint, the package tests on Linux, and builds both packages and the app for the
iOS Simulator. Locally, `scripts/test.sh all` runs every package test and `scripts/lint.sh` runs swift-format, SwiftLint
and the architecture and log-privacy checks.
