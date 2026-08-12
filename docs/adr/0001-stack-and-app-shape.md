# ADR-0001: Swift 6 + SwiftPM, SwiftUI MenuBarExtra, shared core library

> **TL;DR:** Menu bar accessory built with SwiftPM + SwiftUI `MenuBarExtra`, unsandboxed, no third-party deps; all parsing and arithmetic in a `SiriIndexCore` library so the app and the planned widget cannot disagree about a number. Accepted 2026-08-12.

- **Status**: Accepted
- **Date**: 2026-08-12
- **Deciders**: Justin

## Context

The app reads five plist files, computes percentages, and draws them. That is the entire workload:
no network, no writes outside its own container, no data path. Two surfaces are wanted — a menu bar
item and a desktop widget — and they must never show different numbers for the same pipeline.

macOS 15+ makes `MenuBarExtra` with `.menuBarExtraStyle(.window)` sufficient for a panel with
progress bars and a per-app drill-down, which a plain `NSStatusItem` menu is not. The app must not
appear in the Dock or the app switcher, which means `LSUIElement` plus an accessory activation
policy — and therefore a real `.app` bundle, since a bare SwiftPM executable has no `Info.plist` and
so no bundle identity for `LSUIElement` to apply to.

Sandboxing is not an option: the report directory lives outside any container, and there is no
entitlement that reaches it. The app must ship unsandboxed and rely on Full Disk Access (ADR-0004).

## Decision

SwiftPM package, Swift 6 language mode, deployment target macOS 15.0, Apple frameworks only. Three
targets: `SiriIndexCore` (a library holding decoding, aggregation, formatting, and the daemon probe),
`SiriAIIndexStatus` (the executable — SwiftUI `MenuBarExtra` and nothing else), and a test target
covering the core. `Scripts/make-app-bundle.sh` wraps the executable in an ad-hoc-signed `.app` with
`LSUIElement`. The widget, when built, depends on `SiriIndexCore` too and adds no arithmetic of its
own.

## Consequences

The two UI surfaces share one implementation of every number, which is the point of the library
split; a formatting or aggregation fix lands in both at once. Tests run against the core without any
UI harness, which is why the suite is fast enough to run on every change.

The costs are real but small. SwiftPM cannot produce an `.appex`, so the widget needs either an
Xcode project or hand-rolled bundling (`BACKLOG.md` WL-1) — this ADR does not decide which. The
bundle is ad-hoc signed, so it is not distributable and its TCC grant is tied to that ad-hoc
identity; re-signing with a real Developer ID will invalidate the Full Disk Access grant and require
re-adding the app. macOS 15.0 as the floor is generous relative to reality: the reports only exist
on systems doing Apple Intelligence indexing.

## Alternatives considered

**AppKit `NSStatusItem` directly.** More control over the status item and no macOS 13 floor. Rejected:
the panel wants progress bars, disclosure rows, and live-updating state, all of which are a few lines
of SwiftUI and a few hundred of AppKit, for a UI nobody will extend much.

**Single executable target, no core library.** Less structure for a small app. Rejected because the
widget is an explicit requirement, and two independent readers of a private plist format is exactly
how the two surfaces end up disagreeing after an Apple change.

**Xcode project from the start.** Would have made the widget trivial. Rejected for now because the
menu bar app is buildable and testable from the command line with SwiftPM alone, and `swift test` in
a loop is the fast path; the Xcode project can be added when the widget is actually built.
