# SiriAIIndexStatus

A macOS menu bar app that shows how far along Apple Intelligence's on-device semantic index is.

macOS 26 builds this index in the background — the vector store that makes Spotlight and Siri search
by meaning — but ships no UI for its progress. CoreSpotlight already writes the numbers to disk;
this app reads them.

## What it shows

- **Menu bar:** the Embedding pipeline's percentage — the vector index, the one that gates semantic
  search working at all.
- **Panel:** every pipeline (Embedding, Keyphrases, Events & orders, ID documents) with its
  percentage, item count, and a per-app breakdown ranked by *remaining* work.
- **Indexer state:** whether `spotlightknowledged.updater` is running right now.
- **Report age:** the figures are checkpoints macOS refreshes roughly daily, not a live feed, so the
  panel always says how old they are.
- **Desktop widget:** small and medium, from the widget gallery under **Semantic Index**.

## Build and install

```sh
swift test                              # 11 tests, ~10 s — SiriIndexCore, the fast inner loop
Scripts/make-app-bundle.sh release      # → build/SiriAIIndexStatus.app, widget included
open build/SiriAIIndexStatus.app
```

The bundle is built by Xcode, not SwiftPM: WidgetKit only finds a widget shipped as an `.appex`
inside the host app, which SwiftPM cannot produce (ADR-0005). `project.yml` is the source of truth
and [XcodeGen](https://github.com/yonaskolb/XcodeGen) regenerates `SiriAIIndexStatus.xcodeproj` from
it; the `.xcodeproj` is committed, so a clone builds with Xcode alone.

**Building under your own Apple Developer team** means replacing the team ID and App Group in four
places, which must agree: `project.yml` (`DEVELOPMENT_TEAM` and both entitlement blocks),
`Sources/SiriAIIndexStatus/SiriAIIndexStatus.entitlements`,
`Sources/SiriAIIndexStatusWidget/SiriAIIndexStatusWidget.entitlements`, and
`SnapshotStore.appGroupID`. macOS app group IDs must start with your team ID.

Move the bundle somewhere stable (`/Applications`) before granting access — the permission is tied
to the app's location and signature.

## Grant Full Disk Access (required)

The reports live in `~/Library/Metadata/CoreSpotlight/`, which macOS protects with TCC. Without
access the app shows an empty panel and a button to fix it.

1. **System Settings → Privacy & Security → Full Disk Access**
2. **+**, then select `SiriAIIndexStatus.app`
3. **Quit and reopen the app** — macOS does not hand the new permission to a running process.

There is no way for the app to request this itself; Full Disk Access has no prompt API. If you
re-sign the bundle with a different identity, the grant is invalidated and must be redone.

Note that a terminal with Full Disk Access can read these files, which is why command-line probing
works before the app does.

## Reading the numbers

Percentages are per pipeline, over the items that pipeline considers eligible. The `all` aggregate
is the headline; the app list beneath it is the breakdown, and the two are never summed (doing so
double-counts every item).

An app sitting at a low percentage is not necessarily the bottleneck — the list ranks by items
remaining, so a large mailbox at 26% outranks a small help index at 2%.

## Project layout

```
Sources/SiriIndexCore/            parsing, aggregation, formatting, daemon probe
Sources/SiriAIIndexStatus/        menu bar app (SwiftUI MenuBarExtra)
Sources/SiriAIIndexStatusWidget/  desktop widget (WidgetKit extension, built by Xcode)
project.yml                       XcodeGen spec — source of truth for the .xcodeproj
docs/adr/                         decisions
docs/notes/                       what we measured about Apple's private surfaces
```

The widget never reads the reports itself: extensions are sandboxed and get no Full Disk Access, so
the app publishes a snapshot into a shared App Group container and the widget reads that (ADR-0005).
It follows that the widget is blank until the app has run once, and says "App not running" rather
than showing a stale figure as if it were live.

MIT licensed — see [LICENSE](LICENSE).

Requires **macOS 26.6 or later**. That is the floor because it is where the completeness reports
first appear — on anything older the app builds and runs but has nothing to read. No third-party
dependencies.
