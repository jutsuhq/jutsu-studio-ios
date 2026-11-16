# Upstream

`HiggsfieldKit` and `JutsuKit` started as a copy of the packages in
[jutsuhq/jutsu-studio](https://github.com/jutsuhq/jutsu-studio) at commit
[`308ca32`](https://github.com/jutsuhq/jutsu-studio/commit/308ca3222a5a03c7b4f41057057cad40d4e2ddd9) (release 0.2.6),
used under the MIT License in [LICENSE](LICENSE). From then on they are maintained here.

Changes from that commit:

- Platforms are iOS 18 (and macOS 26, so `swift test` runs on a Mac without a simulator); tools version 6.2.
- `JutsuMCP` (the `jutsu mcp` server for local agents), `JutsuAgent` (the agent socket the `jutsu` helper used) and
  their tests are removed.
- Code only the Mac app reached is removed with its tests:
  - `Presentation`: the agents' stack (`Agent*`, the agent path of `ReferenceGenerator.submit`, `onRunEnded`),
    `SubtitleRuns`, `OnDeviceRuns`, `SpeechModels`, `OnDeviceContent`, `SubtitleContent`, `MenuBarPanel`,
    `MenuBarMode`, `Shortcuts` (and Library culling's key presses), `WindowLifecycle`, `OpenedFiles`, `LinkImport`,
    `BackgroundPolicy`, `QueueProblems`, `QueuedNotice`, `LoginItemStatus`, `SignOutConfirmation`, `OldDrafts`,
    `LibraryOrigin`, `JobNotification` and `JobTransitionTracker` (the app posts its own, in
    `App/System/Notifications.swift`), and the menu-bar, output-folder and Queue-problem settings keys.
    `AgentExports.existingNames` is `ExportFolder.existingNames`.
  - `MediaKit`: `ClipJoiner`, `FrameGrab` (with `+Write`), `OnDeviceEnhancer`, `SmoothMotionRenderer`,
    `SuperResolutionRenderer`, `FramePipeline` (its `FrameLoop` stays for the re-encode), `OnDeviceSpeech`,
    `BuiltInSpeech`, `ModelDownloader`, `PreviewExport` and `LocalImage.reopened()`.
  - `Persistence`: the custom output folder (`FileLayout` bookmarks, `OutputFolderHistory`) and
    `FileLayout.moveToTrash`; `LibraryTrash` is `LibraryFiles`, which removes a deleted result's file.
- Bookmarks use plain options on iOS, where security-scope bookmark options don't exist.
- Texts iPhone shows say this device instead of this Mac, and a deleted result is deleted, not moved to the Trash.
- Free disk space counts purgeable space on iOS too.

Fixes to the Higgsfield clients land upstream first. Check `Packages/HiggsfieldKit` there for changes after this
commit and port them.
