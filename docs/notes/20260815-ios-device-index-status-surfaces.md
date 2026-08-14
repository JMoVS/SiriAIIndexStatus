# What an iOS device exposes about its semantic index (2026-08-15)

> **TL;DR:** iOS keeps no readable completeness report — not in a sysdiagnose, not in the analytics
> dumps, not behind any `devicectl` file domain, so the Mac app cannot show a device's percentage.
> With Apple's own Spotlight logging profile installed, the unified log does carry a per-item
> embedding event stream tagged with the donating bundle ID, which makes a donation-pipeline test
> possible. Events, never percentages.

Measured against **iPad Pro 11-inch M4 (iPad16,4), iPadOS 26.6 build 23G71**, Developer Mode on,
paired to this Mac over a hotspot. Question: can the Mac app show a dev device's index status, and
can a developer see how far along their own app's donations are?

**Answer: no per-app or per-pipeline completeness is available on iOS by any host-side route.** The
completeness reports are not in a sysdiagnose, not in the analytics dumps, and not reachable through
any devicectl file domain. Job-level throughput is available in the unified log; identity is not —
*unless* Apple's own Spotlight logging profile is installed, which turns on a per-item embedding
event stream carrying the donating bundle ID. Events, not percentages. See the last two sections.

## The daemon is the same

`xcrun devicectl device info processes` shows `/usr/libexec/spotlightknowledged.updater` (pid 379) —
the same writer identified on macOS (ADR-0002), alongside `siriknowledged`, `knowledgeconstructiond`,
`intelligenceplatformd`. So the device almost certainly writes the same
`completenessReport_*.plist` files under `/var/mobile/Library/Metadata/CoreSpotlight/`. Nothing on
the host can read them.

## Route 1 — devicectl file access: no

`devicectl device copy from` / `device info files` accept exactly four domains:
`temporary` · `appDataContainer` · `appGroupDataContainer` · `systemCrashLogs`. No system-path
domain. AFC reaches `/var/mobile/Media` only; house_arrest reaches dev-signed app containers only.

`systemCrashLogs` **is** readable and was used for the pulls below, but holds no index artifacts
beyond the heartbeat.

## Route 2 — sysdiagnose: no

`xcrun devicectl device sysdiagnose` → 303 MB, 1,572 entries. Searched the full listing:

- `completeness` → **0 matches**. `PipelineCompletenessReporting` → **0 matches**.
- The only CoreSpotlight artifact is `logs/Search/CoreSpotlight/heartbeat.plist` (12 KB).

That heartbeat is the classic `searchd` index heartbeat, not the AI pipelines: `index_a`…`index_cx`
sub-dicts with `count_add_journaled`, `count_delete_processed`, `num_index_gen_compacted`,
`max_journal_file_bytes`, `creation_version_spotlight`. No pipeline names, no bundle IDs, no
percentages. Same file is served live at
`systemCrashLogs:DiagnosticLogs/Search/spotlight_heartbeat_last.log` (process `searchd`), so it can
be pulled without taking a sysdiagnose at all.

Older sysdiagnoses still on the device (23E246 from March, 23E254 from April) carry
`logs/Search/CoreSpotlight` as an **empty** directory — the collector predates any content.

## Route 3 — analytics / telemetry dumps: no

Pulled `Analytics-2026-08-14-080003.0005.ips.ca.synced` (295 KB) from `systemCrashLogs`. 104 distinct
CoreAnalytics event names; none mention spotlight, knowledge, completeness, embedding, or index.
`knowledgeconstructiond` appears only as a process name in a footprint event.

Cross-checked on macOS: 273 `*.core_analytics` files in `/Library/Logs/DiagnosticReports/`, zero
CoreSpotlight or knowledge event names. Nearest neighbours are Apple Intelligence's unrelated
`SummarizationPipelineStatisticsV13` / `NotificationPipelineStatisticsV4`.

## Route 4 — unified log: throughput yes, identity no

The sysdiagnose's `system_logs.logarchive` (452 MB) is queryable with `log show --archive`. Relevant
subsystems, by message count over ~36 h:

| subsystem:category | count |
| --- | --- |
| `com.apple.spotlightindex:Query` | 1326 |
| `com.apple.spotlightknowledge:Scheduler` | 681 |
| `com.apple.corespotlight:query` | 631 |
| `com.apple.spotlightknowledge:ProcessorRegistry` | 462 |
| `com.apple.spotlightknowledge:JournalProcessingJob` | 314 |
| `com.apple.spotlightknowledged.pipeline:Default` | 80 |
| `com.apple.spotlightindex:IVFVectorIndex` | 46 |

**Public** (usable): job names and item counts.

```
JournalProcessingJob.Embedding.InstantProcessing.ClassC ran on 0 items.
Processed 0 items.
Did not process 0 items.
Submitted 0 of 0 updates.
ReindexJob ran on 40 items. Reindexed 40 items.
```

Job names observed: `JournalProcessingJob.Embedding.InstantProcessing.{ClassA,ClassB,ClassC,ClassCX,
MailIndex,PriorityIndex}` and `JournalProcessingJob.Embedding.Priority.ClassC`. The data-protection
class suffixes and `MailIndex` are the closest thing to a per-source breakdown that is public.

**Redacted** (`<private>`), which is exactly the part a developer would need:

```
[com.apple.spotlightknowledged.pipeline:Default] [Processing <private>] Start processing for <private>
[com.apple.spotlightknowledge:Scheduler] Running Priority Reindex for pipeline <private>
[com.apple.spotlightknowledge:ProcessorRegistry] Loaded processor <private>. Handle <private>
[com.apple.spotlightknowledge:SpotlightKnowledge] ### RECEIVED JOURNAL EVENT <private>
… Execution time: <private> seconds. Full report: <private>
```

Bundle IDs, pipeline identity in the Scheduler lines, and the per-job "Full report" payload are all
private. This matches what ADR-0002 recorded on macOS and is why log scraping was rejected there.

Scheduling on iOS is BGST/DAS, not a power-gated launchd job: `com.apple.spotlightknowledged.task.
priority` launched ~every 5–15 min. Different from the macOS `RequiresExternalPower` behaviour in
`20260812-what-schedules-the-completeness-reports.md`.

## Un-redacting the log needs Apple's own profile — a home-made one cannot work

Tried and rejected: a hand-authored `.mobileconfig` carrying a `com.apple.system.logging` payload
with `Enable-Private-Data` for `com.apple.spotlightknowledge`,
`com.apple.spotlightknowledged.pipeline`, `com.apple.corespotlight` and `com.apple.spotlightindex`.

- `devicectl device profile validate` rejects a bare XML profile — it wants a CMS/PKCS#7 envelope
  (error 22104). Wrapping it with `openssl smime -sign` under a self-signed cert clears that.
- `devicectl device profile install` then transfers it, but it never appears in Settings as a
  pending profile. Delivering the same file through iCloud Drive gets as far as an
  unsigned/incorrectly-signed alert with no way to continue.
- Cause is not the signature. **Only Apple can author logging profiles for iOS**; the
  `com.apple.system.logging` payload is macOS-only for third parties
  ([Apple Developer Forums](https://developer.apple.com/forums/thread/705868)). The daemon reports a
  signature error even when signing is not the problem.

## Apple's own profile does work — and it gives per-bundle embedding events

Installed Apple's **`Spotlight.mobileconfig`** ("Spotlight Diagnostics Profile",
`com.apple.Spotlight.logging.profile`) from
[developer.apple.com/bug-reporting/profiles-and-logs](https://developer.apple.com/bug-reporting/profiles-and-logs/).
Apple ID login required, so it cannot be fetched unattended; it self-removes after 7 days
(`DurationUntilRemoval: 604800`). Decode it with `security cms -D -i Spotlight.mobileconfig`.

Two payloads, and the second one is the surprise:

1. `com.apple.system.logging` — Debug level and `Default-Privacy-Setting: Public` for
   `com.apple.corespotlight`, `com.apple.spotlight`, `com.apple.spotlightindex`,
   `com.apple.useractivity`. **`com.apple.spotlightknowledge` is not in the list.**
2. `com.apple.defaults.managed` — writes to `.GlobalPreferences`: `CSLogDetailedActivity: true`,
   `CSLogToConsole: true`, `CSLogToFile: true`, `SPLogLevel: 7`, `SPOutputLevel: 7`.

That defaults payload is what reaches the Apple Intelligence daemon, which the logging payload does
not cover. Measured across two sysdiagnoses of the same device:

| message | before | after |
| --- | --- | --- |
| `spotlightknowledge:SpotlightKnowledgeEmbedding` lines | **0** in 13 h | **88** in 28 min |
| `[Donation … ]` lines | **0** | 210 |

And the line a developer actually wants:

```
[com.apple.spotlightknowledge:SpotlightKnowledgeEmbedding] [Document Embedding Generation]
Start primary embedding generation for item bundleID com.apple.MobileSMS. 1 retries left.
```

Emitted per item, primary and secondary pass, **with the bundle ID in the clear** — observed for
`com.apple.MobileSMS`, `com.apple.mobilephone`, `com.apple.CloudDocs.iCloudDriveFileProvider`,
`com.apple.FileProvider.LocalStorage`. The journal stage above it is attributed only by stable
masked hash:

```
[JournalProcessingJob.Embedding.InstantProcessing.ClassC]
[Donation 443251 for <mask.hash: 't53Mqntiv4jwDQfuLtfSlg=='> in <mask.hash: 'JYCYdKFwVDrWMWziC6frqQ=='>]
Record passed checks. Continuing processing.
```

70 distinct item hashes inside 5 distinct container hashes over the window. `mask.hash` is not
lifted by the private-data setting, but the hashes are stable, so a developer can identify their own
by donating a known item and watching which hash appears.

`com.apple.corespotlight` gets much louder too (1,092 lines over ~36 h before → 2,208 over 30 min
after), with donation-layer bundle attribution: `Handle job type 17 from com.apple.MobileSMS`,
`==== SENDING WORK 17 com.apple.CloudDocs.iCloudDriveFileProvider for type:… count:1`,
`deleteSearchableItemsWithDomainIdentifiers, bundleID:com.apple.shortcuts`,
`CSInlineDonation:com.apple.mobilemail: Skipping donation (feature flag disabled)`.

**What this is and is not.** It is a per-item event stream attributed to a bundle ID: "the index is
embedding this app's donations, right now". It is not completeness — no eligible-item count, no
percentage, no equivalent of the macOS reports. A developer can count events over a window and see
their own app appear or fail to; they cannot learn how much is left.

### As a donation-pipeline test

Three observable stages, two of them carrying the raw bundle ID:

| stage | subsystem:category | attribution | says |
| --- | --- | --- | --- |
| 1. donation arrives | `corespotlight:index` | **bundle ID** | `SENDING WORK 17 <bundle> for type:<uti> (slow:1) count:N`, `deleteSearchableItemsWithDomainIdentifiers, bundleID:…`, `CSInlineDonation:<bundle>: Skipping donation (feature flag disabled)` |
| 2. record validated | `spotlightknowledge:JournalProcessingJob` | mask.hash only | `[Donation N for <hash> in <hash>] Validating record` → `Record passed checks. Continuing processing.` |
| 3. embedding generated | `spotlightknowledge:SpotlightKnowledgeEmbedding` | **bundle ID** | `Start primary/secondary embedding generation for item bundleID <bundle>. 1 retries left.` |

Stage 1 present and stage 3 absent is the failure a developer would actually want to catch: the
donation landed and nothing embedded it.

**Stage 3 logs no outcome.** Across the whole archive the only shape is `Start … 1 retries left` —
44 primary, 44 secondary, zero completion or failure lines. A retry would presumably surface as
`0 retries left`; never observed, so untested. Absence of a follow-up is not evidence of success.

### The mask.hash values cannot be computed, only correlated

16 bytes, base64. The hash is applied by the logging system under a salt that is not exposed to
apps, and Apple's stated purpose for `mask.hash` is correlation without disclosure — there is no API
or documented algorithm to reproduce one from a known identifier, so a developer cannot precompute
their item's hash and grep for it.

What works instead is correlation by construction: donate a known item at a known time and the hash
that appears is yours. Measured stability — of 4,303 distinct `mask.hash` values in the 23:58
collection, **3,749 recur** in the 00:26 collection, so a hash identified once stays usable.
Cross-reboot stability is untested (it would need a reboot and a third collection).

## Public API, for the "is my app's donation indexed" question

No completeness API exists. `CSSearchableIndex.h` (iPhoneOS26.5 SDK) offers `isIndexingAvailable`,
`fetchLastClientState`, and nothing about progress. Two APIs answer a narrower question from inside
the developer's own app:

- `searchableItemsForIdentifiers:searchableItemsHandler:` (iOS 18.4) — ask the index to hand your own
  items back. Ground truth for "did the donation land", per identifier.
- `CSUserQuery` with `CSUserQueryContext.disableSemanticSearch = NO` (iOS 18) — whether the item is
  retrievable *by meaning*, i.e. embedded rather than merely stored. No entitlement in the header.

Both are per-item probes run by the app itself, not observation from a Mac.

## Artefacts

Pulls live in the session scratchpad, not the repo: `ipad-sysdiag/sysdiagnose_2026.08.14_23-58-16
+0800_iPhone-OS_iPad_23G71_*.tar.gz` (303 MB), `ipad-analytics.ips`, `spotlight_heartbeat.log`,
`sysdiag-listing.txt`, `sk.log`.
