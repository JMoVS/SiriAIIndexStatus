# ADR-0005: Build the bundle with Xcode, and feed the widget through an App Group snapshot

> **TL;DR:** SwiftPM cannot emit an `.appex`, so the shipping bundle is built by a generated Xcode project that consumes the SwiftPM package; and because the widget extension is sandboxed and gets no Full Disk Access of its own, the app publishes a JSON snapshot into a shared App Group container and the widget only ever reads that. Accepted 2026-08-12.

- **Status**: Accepted
- **Date**: 2026-08-12
- **Deciders**: Justin

## Context

Two independent problems arrived together, both from the same source: WidgetKit only discovers a
widget shipped as an `.appex` inside the host app's `Contents/PlugIns/`.

**Building it.** SwiftPM has no app-extension product type. The widget's implementation had been sat
in `Sources/SiriAIIndexStatusWidget/` since the first pass, compiled by nothing.

**Feeding it.** App extensions must be sandboxed — that is not a choice. So the widget cannot use the
route the app uses (unsandboxed + Full Disk Access, ADR-0004): no entitlement gets a sandboxed
process into `~/Library/Metadata/CoreSpotlight/`. An extension does not inherit its host's TCC grant
either; it runs out-of-process under its own identity. A widget that called `ReportLoader.loadAll()`
directly would have shown a permission error forever.

## Decision

**`project.yml` + XcodeGen generate `SiriAIIndexStatus.xcodeproj`,** with an application target and an
`app-extension` target, both depending on the *local SwiftPM package* rather than duplicating its
sources. `project.yml` is the source of truth; the generated `.xcodeproj` is committed too, so a
clone builds without XcodeGen installed. `Scripts/make-app-bundle.sh` regenerates and drives
`xcodebuild`, then copies the result to the stable `build/SiriAIIndexStatus.app`.

**The app publishes, the widget reads.** `SnapshotStore` (in `SiriIndexCore`) writes
`snapshot.json` — status, capture time, and the app's last error — atomically into the App Group
container. `StatusStore` publishes after every refresh and calls
`WidgetCenter.reloadAllTimelines()` only when a number actually moved. The widget's timeline
provider does one thing: read that file.

The App Group is `5CYP2XRG73.de.justinscholz.SiriAIIndexStatus`. macOS requires the Team ID prefix;
the bare `group.` form is the iOS convention.

## Consequences

The signature changed from ad-hoc to a provisioned Apple Development identity, because an App Group
container is only created for a provisioned one. As ADR-0004 predicted, **that invalidated the
existing Full Disk Access grant** — the old bundle had to be removed from the list and the new one
added. Every future change of signing identity costs the same re-grant.

The widget is never more current than the app, and is blank until the app has run once. That is
visible rather than hidden: `capturedAt` older than an hour means the app is not running (its poll
is 10 minutes), and the widget says "App not running" rather than showing a stale percentage as if
it were live. Two kinds of "old" — the reports' own age and the app's — stay distinguishable.

The repo now has two build paths. `swift build` / `swift test` still cover `SiriIndexCore` and the
app sources and stay the fast inner loop; `xcodebuild` is only for producing the bundle. They cannot
disagree about arithmetic, because both compile the same package.

`DEVELOPMENT_TEAM` and the App Group ID are hard-coded in `project.yml`, both entitlements files and
`SnapshotStore.appGroupID`. Building under another team means changing all four.

## Alternatives considered

**Hand-roll the `.appex` in `make-app-bundle.sh`** — build the widget as a SwiftPM executable, then
assemble the bundle layout, `Info.plist` and signature by hand. Keeps the repo Xcode-free, which
ADR-0001 valued. Rejected: the entitlements and provisioning an App Group needs are exactly the part
that would have been hand-rolled, and ad-hoc signing does not get a group container at all.

**Give the widget its own Full Disk Access grant.** Rejected: extensions are sandboxed, so no grant
would have helped; and even if it worked it would mean a second entry in the Settings list and two
processes duplicating the same parse.

**A plain shared file outside any container** (e.g. in `/tmp` or the app's own support directory).
Rejected: the widget's sandbox cannot read it. The App Group *is* the mechanism for this.

**`UserDefaults(suiteName:)` instead of a JSON file.** Same container, less control. Rejected: the
snapshot is a document, not a preference, and atomic file replacement is the behaviour we want when
a widget can wake mid-write.
