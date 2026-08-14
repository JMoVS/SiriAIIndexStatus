# SiriAIIndexStatus

**Is Apple Intelligence finished indexing my Mac yet?** On iPhone, Settings tells you — indexing
progress is right there in the UI. On macOS, Apple built no such screen. This is that missing UI: a
menu bar app that answers the question in one glance.

Semantic search — Spotlight and Siri finding things by *meaning* rather than by filename — only works
once the system has built a vector index of your mail, files, calendar, and messages. That happens
quietly in the background over days. macOS writes the progress numbers to disk and then shows them to
nobody. This app reads them and puts the percentage in your menu bar.

## What you see

- **In the menu bar:** one percentage — how much of your content has been embedded. This is the one
  that gates semantic search working at all.
- **In the panel:** every indexing pipeline (embeddings, keyphrases, events & orders, ID documents),
  with a per-app breakdown — Mail, Calendar, Notes, Messages, iCloud Drive, third-party cloud
  storage — ranked by how much work is left.
- **Whether it is working right now:** the app shows whether the indexer process is running.
- **How fresh the figures are:** macOS refreshes these numbers roughly once a day, so they are
  checkpoints, not a live feed. The panel always tells you how old they are — a figure that has not
  moved in three days means macOS has not run the job, not that nothing is happening.
- **A desktop widget** (small and medium), if you would rather keep an eye on it from the desktop.

Nothing leaves your Mac. The app reads local files, makes no network connections, and writes only
inside its own container.

## Install

There is no signed download yet, so you build it — two commands, and you need Xcode installed:

```sh
Scripts/make-app-bundle.sh release      # → build/SiriAIIndexStatus.app
open build/SiriAIIndexStatus.app
```

Move the app to **/Applications** before the next step. Full Disk Access is tied to where the app
lives and how it is signed, so granting it and *then* moving the app invalidates the grant.

## Grant Full Disk Access (required)

The numbers live in a folder macOS protects (`~/Library/Metadata/CoreSpotlight/`). Until you allow
access, the app shows an empty panel with a button that takes you to the right settings pane.

1. **System Settings → Privacy & Security → Full Disk Access**
2. Click **+** and pick `SiriAIIndexStatus.app`
3. **Quit and reopen the app.** macOS does not hand the new permission to an already-running app.

The app cannot ask for this itself — Full Disk Access has no prompt, by Apple's design. That is also
why the app cannot do anything sneaky with the access: the source is right here, and it is
read-only.

## Reading the numbers

- **Each percentage is per pipeline**, over the items that pipeline considers eligible. They are not
  a single "Apple Intelligence is 84% ready" number, and the app does not invent one.
- **The aggregate is the headline; the app list underneath is the breakdown.** They are never added
  together — that would count every item twice.
- **A low percentage is not automatically your bottleneck.** The list ranks by *items remaining*, so
  a big mailbox at 26% is more of the outstanding work than a small help index at 2%.
- **Frozen figures usually mean power, not failure.** The job macOS uses to write these reports wants
  external power. On battery, expect the numbers to stand still.
- **For third-party cloud storage, a high percentage promises less than it looks like.** Files that
  are not downloaded get indexed by name and date only, not by content — see
  `docs/notes/20260812-fileprovider-materialization.md` for the measurements behind that.

Requires **macOS 26.6 or later** — that is where these reports first appear. On anything older the
app runs but has nothing to read.

## Building from source

```sh
swift test                              # 17 tests, ~10 s — the parsing and aggregation core
Scripts/make-app-bundle.sh release      # full bundle, widget included
```

The bundle is built by Xcode rather than SwiftPM: WidgetKit only finds a widget shipped as an
`.appex` inside the host app, which SwiftPM cannot produce (ADR-0005). `project.yml` is the source of
truth and [XcodeGen](https://github.com/yonaskolb/XcodeGen) regenerates the `.xcodeproj` from it; the
`.xcodeproj` is committed, so a clone builds with Xcode alone.

**Signing under your own Apple Developer team** means replacing the team ID and App Group in four
places, which must agree: `project.yml` (`DEVELOPMENT_TEAM` and both entitlement blocks),
`Sources/SiriAIIndexStatus/SiriAIIndexStatus.entitlements`,
`Sources/SiriAIIndexStatusWidget/SiriAIIndexStatusWidget.entitlements`, and
`SnapshotStore.appGroupID`. macOS App Group IDs must start with your team ID.

```
Sources/SiriIndexCore/            parsing, aggregation, formatting, daemon probe
Sources/SiriAIIndexStatus/        menu bar app (SwiftUI MenuBarExtra)
Sources/SiriAIIndexStatusWidget/  desktop widget (WidgetKit extension, built by Xcode)
project.yml                       XcodeGen spec — source of truth for the .xcodeproj
docs/adr/                         decisions, and why
docs/notes/                       what we measured about Apple's private surfaces
```

The widget never reads the reports itself: extensions are sandboxed and get no Full Disk Access, so
the app publishes a snapshot into a shared App Group container and the widget reads that (ADR-0005).
Hence the widget stays blank until the app has run once, and says "App not running" rather than
showing a stale figure as if it were live.

No third-party dependencies. The formats this app reads are private to Apple and undocumented; every
value we derived from one has a test with the real observed numbers in it, which is how we will find
out when Apple changes something.

MIT licensed — see [LICENSE](LICENSE).
