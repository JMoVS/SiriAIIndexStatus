# ADR-0003: The `all` row is the headline, never a sibling

> **TL;DR:** Each pipeline's `bundleID == "all"` row is its own aggregate; it is the displayed headline and is excluded from the per-app list. Summing it alongside the per-app rows double-counts every item — the error that produced a 404,894-item total for a 202,447-item pipeline. Accepted 2026-08-12.

- **Status**: Accepted
- **Date**: 2026-08-12
- **Deciders**: Justin

## Context

Each `completenessReport_<pipeline>.plist` holds one row per donating app plus one row whose
`bundleID` is the literal string `all`. Nothing in the archive marks that row as special — it has the
same shape and the same fields as `com.apple.mail` beside it.

During the first reconnaissance pass, the rows were treated uniformly and an item-weighted mean was
computed across all of them. That reported "48.7% of 404,894 eligible items" for the Embedding
pipeline. The true figure is 48.7% of **202,447**: the aggregate row carries the pipeline's whole
population, so including it alongside its own components counts every item exactly twice. The
percentage survived by luck — a weighted mean that double-counts uniformly still lands on the right
ratio — but the population was wrong, and a differently-weighted mistake would have moved the
percentage too.

## Decision

When folding rows into a `PipelineProgress`, partition on `isAggregate`. The `all` row supplies
`completeness` and `eligibleItems` for the pipeline headline; the remaining rows become `apps` and
are never summed into the headline. If a pipeline has no `all` row, derive the headline as an
item-weighted mean over the per-app rows and flag it `headlineIsDerived` so the UI can mark it as an
estimate. Laggards rank by *remaining* items — `eligibleItems × (1 − completeness)` — not by
percentage, because the pipeline is held up by the app with the most work left, not the lowest score.

## Consequences

Headline figures match what Apple itself recorded rather than a reconstruction, and the per-app list
stays a genuine breakdown. The `headlineIsDerived` flag means a future pipeline that ships without an
aggregate row still displays, visibly labelled as estimated rather than silently guessed.

We depend on the string `all` keeping its meaning. If Apple ever ships a real app with that bundle
id, or renames the aggregate, the headline silently becomes one app's progress — a wrong number that
looks plausible. The guard is `IndexStatusBuilderTests.testAggregateRowIsTheHeadlineAndIsNotCountedTwice`,
which pins the real observed values; it fails loudly if the partition stops working.

## Alternatives considered

**Always derive the headline from the per-app rows and ignore `all`.** Removes the dependency on a
magic string. Rejected: Apple's own aggregate is authoritative and may count items no per-app row
reports; deriving would quietly disagree with the system's own number.

**Show the `all` row as just another entry in the per-app list.** Simplest possible handling.
Rejected: it reads as an app, sorts among the apps, and invites exactly the double-count this ADR
exists to prevent.
