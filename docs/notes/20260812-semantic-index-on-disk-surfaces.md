# Semantic index: on-disk surfaces and who writes them

> **TL;DR:** On macOS 26.6.1 (25G76) the Apple Intelligence semantic index reports progress in
> `~/Library/Metadata/CoreSpotlight/PipelineCompletenessReporting/*.plist`, written by
> `spotlightknowledged.updater` (confirmed by `lsof` holding the `cs_mail` embedding store open).
> Five pipelines; Embedding was 48.7% of 202,447 items on 2026-08-11. Reports refresh ~daily.

Measured 2026-08-12 on macOS 26.6.1, build 25G76.

## Processes

Running and relevant:

| Process | Role |
|---|---|
| `spotlightknowledged.updater` (`/usr/libexec/`) | **Writes the index.** Held `SpotlightKnowledgeEvents/index.V2/embedding_cache/10/4/cs_mail/embedding_store.db` open during observation. |
| `spotlightknowledged` (`CoreSpotlight.framework/`) | Daemon front end; held none of the store files. |
| `corespotlightd` | Classic Spotlight metadata index, distinct from the semantic one. |
| `siriknowledged`, `intelligencecontextd`, `intelligenceflowd` | Consumers of the index, not writers. |
| `mediaanalysisd` | Image/media analysis; feeds its own embeddings. |
| `knowledge-agent` + `~/Library/Application Support/Knowledge/knowledgeC.db` | **Unrelated.** Legacy Duet usage-statistics DB, predates all of this. Do not confuse it with the semantic index. |

`pgrep -x spotlightknowledged.updater` matches despite the name being 27 characters — no `MAXCOMLEN`
truncation problem in practice (verified: returns the pid).

## Storage layout

Under `~/Library/Metadata/CoreSpotlight/`:

- `PipelineCompletenessReporting/completenessReport_<pipeline>.plist` — **the progress figures.**
- `SpotlightKnowledge/index.V2/` — knowledge graph (`KG/kg` + wal/shm), `DocumentProcessing/`,
  journals, deletes, per-protection-class subdirectories.
- `SpotlightKnowledgeEvents/index.V2/embedding_cache/<n>/<n>/<client>/embedding_store.db` — **the
  vectors**, with `.map.buckets` / `.map.data` / `.map.header` / `.map.offsets` sidecars.
- `NSFileProtection{Complete,CompleteUnlessOpen,CompleteUntilFirstUserAuthentication}/index.spotlightV3/`
  — the classic index, partitioned by data-protection class.
- `FileProviderDomains.plist` — file provider domains participating in indexing (Photos, iCloud
  Drive, Mountain Duck, Nextcloud observed).

The whole directory is TCC-protected. Shell reads succeed only because the terminal holds Full Disk
Access; a fresh app bundle gets `NSFileReadNoPermissionError` (ADR-0004).

## Report format

`NSKeyedArchiver` archive. Root is an `NSArray` of `CSPipelineCompletenessReport` objects with keys:

| Key | Type | Notes |
|---|---|---|
| `pipeline` | `NSString` | e.g. `Embedding` |
| `bundleID` | `NSString` | donating app, or `all` for the aggregate (ADR-0003) |
| `pipelineCompleteness` | `NSNumber` | 0…1 |
| `pipelineCompletenessHeuristicScore` | `NSNumber` | equal to `pipelineCompleteness` in every observed row |
| `eligibleItems` | `NSNumber` | in-scope item count |
| `reportDate` | `NSDate` | identical across all rows of a file |
| `pipelineCompleteness{FirstTime,Second,Third}Bucket` | `$null` | unpopulated in every observed row |

Every scalar is an object reference to an `NSNumber`, not an inline primitive — `decodeInteger(forKey:)`
returns 0 for all of them.

## Measured state, 2026-08-11 12:04 (read 2026-08-12)

| Pipeline | Complete | Eligible items |
|---|---|---|
| `Embedding` | 48.7% | 202,447 |
| `LSSR5EventsandordersUrgent` | 19.6% | 89,383 |
| `LSSR5EventsandordersBackground` | 11.8% | 148,427 |
| `Keyphrase` | 1.2% | 106,408 |
| `LSSR5IdentificationdocumentsBackground` | 0.0% | 7,648 |

Embedding per-app, worst first: Help Viewer 2.2% (8,642) · Messages 19.9% (8,781) · Mail 26.1%
(118,195) · Notes 28.1% (352) · Safari 54.7% (148) · Mountain Duck 73.5% (495) · Shortcuts 81.8%
(478) · System Settings 98.4% (696) · Nextcloud 99.0% (38,700) · Calendar 99.9% (24,813) · Reminders,
OmniFocus, Excel, PowerPoint, Podcasts, Phone, App Store, app placeholders all 100%.

Mail dominates the remaining work: ~87,000 items outstanding, more than every other app combined.

## Live observation

`log stream --predicate 'process CONTAINS "spotlightknowledged"'` shows the scheduler loop
(`JournalProcessingJob.Embedding.InstantProcessing.ClassC`) firing per journal event, but item counts
and job identities log as `<private>`. Useful for confirming the daemon is alive; useless for
progress without system-wide private-data logging.

## Open questions

- Does the file provider indexing of Nextcloud/Mountain Duck materialise dataless files? Nextcloud
  reached 99% of 38,700 items and the domain is registered in `FileProviderDomains.plist`; spot
  checks found files still marked `dataless`. Unresolved — see the operator's question of
  2026-08-12.
- What triggers a report refresh? Every row shared one `reportDate`, ~23 h stale, while the updater
  was actively running. Cadence inferred as ~daily, not confirmed.
