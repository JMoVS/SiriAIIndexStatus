# ADR-0006: Keep our own log of past readings, and compare each pipeline against its own previous report

> **TL;DR:** macOS overwrites `completenessReport_<pipeline>.plist` in place, so the reports carry no
> history and "how much was indexed since yesterday" is unanswerable from disk. The app keeps its own
> append-only log of readings, one entry per distinct report date, and computes the delta per pipeline
> against that pipeline's own previous report — leading with the item count, not the percentage.
> Accepted 2026-08-26.

- **Status**: Accepted
- **Date**: 2026-08-26
- **Deciders**: Justin

## Context

The panel could say how complete the index is and how old that figure was, but not whether anything
had happened. A percentage that has not moved and a percentage nobody has re-read look identical.

The reports cannot answer it. The daemon writes one file per pipeline and overwrites it; yesterday's
figures are gone the moment today's are written. Nothing else on the system keeps them — the
embedding stores are an undocumented binary format (`docs/notes/20260812-embedding-store-format.md`)
and the daemon's own logs are mostly `<private>`.

## Decision

**The app records what it reads.** `HistoryStore` keeps an append-only JSON log of `IndexObservation`
values in the App Group container beside `snapshot.json`, falling back to Application Support when an
unsigned local build has no container. One entry per distinct report date, capped at 60 — about two
months of daily checkpoints.

**Re-reads replace, they do not append.** `StatusStore` polls every ten minutes and the reports move
about once a day, so roughly 140 of every 144 readings are the same checkpoint again. Appending those
would push the only useful comparison out of the log within half a day.

**Empty or undated readings are never recorded.** A failed read deliberately leaves the last good
status on screen; writing `.empty` into the log would invent a checkpoint at zero and report the next
real reading as a day of miraculous progress.

**Each pipeline is compared against its own previous report,** not against one global baseline for the
whole log. The five pipelines are written by separate jobs and do not all move on the same day. A
global baseline would report "no change" for every pipeline that missed the latest write — a fact
about the report schedule, dressed up as a fact about indexing.

**The item count leads; the percentage follows.** The eligible set grows as apps donate, so the
percentage can fall on a day the indexer got through thousands of items. Reporting only the
percentage would call that day a regression. The panel shows `+10,339 indexed in 24 h · 48.7% →
52.6%`, and `4,775 more items added to the total` on its own line when the denominator moved.

Both ends of the percentage, not the difference between them: `+3.9 pp` was the first wording and it
did not survive contact with its first reader — "pp" is jargon, and a bare `+3.9` beside a percentage
reads as a percentage of a percentage. The eligible-set line is spelled out for the same reason:
`+4,775 eligible` reads as the size of the backlog rather than the growth of it, and "eligible" is
the report's word, not a reader's — "added to the total" names the item count on the line above,
which is what the percentage is measured against.

**An app absent from the earlier report is marked `new`, not credited with progress.** Its whole count
arrived at once; calling that a day's indexing would overstate every new donor.

## Consequences

- The comparison only exists for checkpoints the app was running to see. A first launch shows "First
  reading — progress appears after the next report", and a Mac that ran nothing for a week compares
  today against whenever the app last ran, with the real span shown beside the figure.
- The log is per-user and local. Deleting it costs the comparison, nothing else.
- The widget shows the headline pipeline's item change on one line. It cannot compute a delta
  itself, so `snapshot.json` carries the whole `IndexDelta` (ADR-0005); the field is optional, and a
  snapshot written before it existed still decodes.
- On battery the report job does not run at all (WL-7), so "no change" there still means "no new
  report", not "no indexing". Freshness and reason-for-staleness remain a separate job.
