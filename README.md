<div align="center">

<img src="docs/assets/icon.png" alt="Jutsu app icon" width="128" height="128">

# Jutsu for iPhone

**An open-source Higgsfield app for iPhone and iPad. Unofficial.** Motion transfer, character swap, restyle and
images on your own Higgsfield account, with the price shown before every generation and every take kept on the device.

[Build](#build-from-source) · [What it does](#what-it-does) · [Architecture](docs/ios-architecture.md) ·
[Website](https://jutsustudio.com/) · [Mac app](https://github.com/jutsuhq/jutsu-studio)

[![License: MIT](https://img.shields.io/badge/License-MIT-8b5cf6.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%2018%2B%20%7C%20iPadOS-000000?logo=apple&logoColor=white)](#at-a-glance)
[![Built with SwiftUI](https://img.shields.io/badge/built%20with-SwiftUI-F05138?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#contributing)
[![Unofficial](https://img.shields.io/badge/unofficial-not%20affiliated%20with%20Higgsfield-e879f9)](#disclaimer)

</div>

---

## At a glance

| | |
|---|---|
| Platform | iPhone and iPad, iOS 18 or later. Liquid Glass on iOS 26 |
| Requirements | A Higgsfield account (plan credits) or a Higgsfield API key (pay as you go). Generation runs on Higgsfield's servers, not on the phone |
| License | MIT |
| Price | The app is free and adds no markup. Higgsfield bills your own account at its prices |
| Languages | English, Russian, Spanish, Brazilian Portuguese, German, French, Japanese, Simplified Chinese |
| Install | Not on the App Store yet. [Build from source](#build-from-source) with Xcode 26 |
| Sibling | [Jutsu Studio for Mac](https://github.com/jutsuhq/jutsu-studio): this app runs on its Swift packages |

<table>
<tr>
<td width="33%"><img src="fastlane/screenshots/en-US/iPhone%206.9%204.png" alt="Create: a clip, its model and options, and the price on Generate"></td>
<td width="33%"><img src="fastlane/screenshots/en-US/iPhone%206.9%203.png" alt="Library: every take on the phone and the account's Higgsfield history"></td>
<td width="33%"><img src="fastlane/screenshots/en-US/iPhone%206.9%206.png" alt="Queue: jobs that keep running in the background"></td>
</tr>
<tr>
<td><b>The price before you generate.</b> Every video and image model with its options, and a cheap draft first.</td>
<td><b>Every take in one place.</b> Results on the phone next to the account's Higgsfield history.</td>
<td><b>Send it and walk away.</b> The queue keeps going in the background and notifies you when it's done.</td>
</tr>
</table>

## What it does

- **Create:** a clip from Photos, Files or the Share sheet; a filmstrip trim with several ranges; a restyle gallery;
  references and start and end frames; every model's options; the price on Generate; draft first, final later.
- **Queue:** jobs grouped by what they need from you; batches; Pause and Resume All; confirm a higher price; job
  details with IDs for support.
- **Library:** takes in a grid; full-screen before and after; keep, reject, star; Render Final; Save to Photos; a swipe
  deck to cull new takes; two takes side by side; the account's Higgsfield history; Export for Editing as ProRes or
  H.264 with a JSON sidecar.
- **In the background:** results download on a background session, unsent jobs keep sending, local notifications and a
  Live Activity in the Dynamic Island.
- **Enhance on Higgsfield:** Upscale, Reframe, Remove Background, Dub and Change Voice, each priced. Nothing heavy runs
  on the phone.
- **Images:** the connection's image models, results usable as references.
- **From Higgsfield:** the Motion Library as a source, the account's elements and character sheets as references,
  Create Character.
- **System:** Home Screen and Lock Screen widget, Shortcuts and Siri, Share to Jutsu.
- **Account:** balance, spending by period, a daily cap, generation defaults, cellular downloads, storage.

## Privacy & safety

- No backend, no accounts of ours, no telemetry. The app talks straight to Higgsfield with your API key or your
  account sign-in (OAuth in a web sheet; the app never sees your password).
- No key ships with the app. Your key and sign-in tokens live only in the iOS Keychain; logs redact credentials and
  signed URLs.
- The source clip, reference images and prompt are uploaded to Higgsfield for each job, and the results are downloaded
  back. Your library, history and settings stay on the device.

## Build from source

Needs a Mac with Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate && open Jutsu.xcodeproj
```

To build under another team, change `DEVELOPMENT_TEAM` and the bundle ID prefix in `project.yml`. Account sign-in also
needs the auth domain (`AUTH_DOMAIN`) to serve the OAuth client metadata and the `apple-app-site-association` file; see
[docs/ios-architecture.md](docs/ios-architecture.md#account-sign-in). An API key works without it.

| Command | What it does |
|---|---|
| `scripts/test.sh all` | Package tests |
| `scripts/test-linux.sh` | The same packages tested on Linux, in Docker |
| `scripts/lint.sh` | swift-format, SwiftLint, architecture and log-privacy checks |

## Docs

- [docs/ios-architecture.md](docs/ios-architecture.md): how the app is put together.
- [docs/higgsfield-api.md](docs/higgsfield-api.md): Higgsfield API reference.
- [Packages/UPSTREAM.md](Packages/UPSTREAM.md): what was copied from the Mac app and what changed.

## Related

Other open-source projects from [Jutsu Studio](https://jutsustudio.com/):

- [Jutsu Studio](https://github.com/jutsuhq/jutsu-studio): the open-source Higgsfield desktop app for Mac
- [Kawarimi](https://github.com/jutsuhq/kawarimi-local-character-swap): free local AI character swap for Windows and Linux, no cloud
- [Swapjutsu](https://github.com/jutsuhq/swapjutsu-seedance-character-swap): free character swap for Mac, no watermark
- [Open Source Higgsfield](https://github.com/jutsuhq/open-source-higgsfield): every #OpenSourceHiggsfield challenge project, by category

## Contributing

Issues and PRs are welcome. Run `scripts/lint.sh` and `scripts/test.sh all` before a PR, and keep the app's
principles: bring your own account, local first, never surprise with cost.

## Disclaimer

Jutsu for iPhone is an **unofficial, community-built tool**. It is not affiliated with, endorsed by, or connected to
Higgsfield AI in any way. Higgsfield, Seedance, Kling and other model names are trademarks of their respective owners.
All generation costs are billed to your own Higgsfield account.

## License

[MIT](LICENSE) © Jutsu Studio contributors
