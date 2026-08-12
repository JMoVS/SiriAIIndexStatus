# ADR-0002: Read the completeness reports, decoded by class substitution

> **TL;DR:** Status comes from `~/Library/Metadata/CoreSpotlight/PipelineCompletenessReporting/*.plist`, decoded by registering our own class for `CSPipelineCompletenessReport` on `NSKeyedUnarchiver` — public API, no UID-graph walking, no private symbols. Reports are ~daily checkpoints, so the UI must show their age. Accepted 2026-08-12.

- **Status**: Accepted
- **Date**: 2026-08-12
- **Deciders**: Justin

## Context

macOS 26 builds the Apple Intelligence semantic index with no user-facing progress UI. Evidence
gathered on 2026-08-12 (`docs/notes/20260812-semantic-index-on-disk-surfaces.md`) found that
CoreSpotlight already writes exactly the figures we want: one plist per pipeline, each holding
`CSPipelineCompletenessReport` rows with `pipeline`, `bundleID`, `pipelineCompleteness`,
`eligibleItems`, and `reportDate`. `spotlightknowledged.updater` was confirmed as the writer by
`lsof` — it holds the `cs_mail` embedding store open while indexing.

The files are `NSKeyedArchiver` archives whose class, `CSPipelineCompletenessReport`, is private to
CoreSpotlight and cannot be linked against. Decoding the archive by hand means walking the `$objects`
UID graph, and Swift cannot read a `CFKeyedArchiverUID` without private API —
`PropertyListSerialization` surfaces UIDs as an opaque bridged type.

The reports are checkpoints. Every row observed carried the same `reportDate`, ~23 h old at the time
of reading, while the updater was actively working. They are not a live progress feed.

## Decision

Read every `*.plist` in the report directory and decode each with `NSKeyedUnarchiver`, calling
`setClass(_:forClassName: "CSPipelineCompletenessReport")` to substitute our own `NSSecureCoding`
type for Apple's. Keep `requiresSecureCoding = true`. A file that fails to decode is skipped, not
fatal, so one unrecognised pipeline cannot blank the whole UI. Daemon liveness is a separate,
best-effort `pgrep -x spotlightknowledged.updater`. Because the figures are stale by construction,
the UI always shows the report age alongside them.

## Consequences

Decoding uses only public API and gets us typed access to every field, including ones we do not yet
display. Each scalar is archived as an object reference to an `NSNumber` rather than an inline
primitive, so `decodeObject(of: NSNumber.self, ...)` is mandatory — `decodeInteger(forKey:)` silently
returns 0 for all of them, which is a wrong-number failure mode rather than a loud one, and is why
the decode path has a test with real observed values in it.

We are coupled to a private format. If Apple renames the class, changes the keys, or moves the
directory, the app shows nothing — it will not show *wrong* numbers, because a decode failure is
visible as an empty state. The ~daily refresh is a hard ceiling on responsiveness: no amount of
polling makes the number fresher, which is why polling is slow (`BACKLOG.md` WL-3) and staleness is
displayed rather than hidden.

## Alternatives considered

**Walk the `$objects` UID graph manually.** Fully format-independent and how the original
reconnaissance was done, in Python. Rejected: reading UIDs from Swift needs `CFKeyedArchiverUIDGetValue`,
which is private, and the hand-rolled resolver is more code than the class substitution it replaces.

**Shell out to `plutil -p` and parse the text.** No archive handling at all. Rejected: parsing a
debug-oriented text dump is brittle in a different and worse way, costs a process spawn per refresh,
and loses type information.

**Scrape `log stream` from `spotlightknowledged`.** Would give live progress rather than daily
checkpoints. Rejected: the interesting payloads log as `<private>`, so item counts are unavailable
without enabling private-data logging system-wide — far too invasive for a status widget.

**Query the embedding stores directly** (`SpotlightKnowledgeEvents/index.V2/embedding_cache/…`).
Closest to ground truth. Rejected: undocumented SQLite-adjacent formats held open by a live daemon;
reading them risks lock contention with the indexer for a number the reports already state.
