# File Provider items and the semantic index: does indexing materialise dataless files?

> **TL;DR:** No. On macOS 26.6.1 (25G76) File Provider items *are* in scope for the Embedding
> pipeline — `com.nextcloud.desktopclient` is a bundleID row in the report, 38,700 eligible items
> against the domain's own 38,908 — but they enter it as **provider-donated metadata**, not file
> content. `fileproviderd` indexes via `(CoreSpotlight) fetch-attributes` → `index-items`, a
> different job class from `fetch-content`/`materialize`. Measured: 405 of 405 sampled *indexed*
> Nextcloud files are still `dataless` with `blocks=0`; 1,896 indexed PDFs in the domain have
> **zero** `kMDItemNumberOfPages`, against 2,949 / 2,949 in a local control directory. Nothing was
> downloaded, so nothing needed evicting. Eviction question is moot, not answered.

Measured 2026-08-12 on macOS 26.6.1, build 25G76. FP version 4018.160.6.
Answers the open question left in `20260812-semantic-index-on-disk-surfaces.md`.

Every claim below is tagged **(D)** documented API contract · **(O)** observed on this machine ·
**(I)** inference from the two.

---

## 1. Scope: File Provider items *are* in the Embedding pipeline

The earlier note guessed the per-`bundleID` rows meant app-donated CoreSpotlight items only. Half
right — the donor can be a File Provider extension, and here it is.

**(O)** The Embedding report names the provider's *containing* bundle, not a display name:

```
$ plutil -p ~/Library/Metadata/CoreSpotlight/PipelineCompletenessReporting/completenessReport_Embedding.plist \
    | rg -i 'nextcloud|mountainduck'
    82 => "io.mountainduck"
   104 => "com.nextcloud.desktopclient"
```

**(O)** `fileproviderctl dump` gives the same domain an indexer with an item count that matches:

```
$ fileproviderctl dump          # com.nextcloud.desktopclient.FileProviderExt, domain 1{34}9
  + indexer:
      spDomainID:     33634D0E-19A9-461C-92BC-16E7F7015036
      enabled:        yes
      indexing:       no
      needs-indexing: no
      + telemetry info:
         count of files requested for redonation in the last day: 0
      errors:         0
      spotlightIndexer:
      eligibleForEmbeddings: true
      pending-indexable-count: 0
      total-indexable-count:  38908
```

**(I)** 38,908 indexable vs 38,700 `eligibleItems` in a ~23 h stale report ⇒ the Nextcloud row of
the Embedding pipeline *is* the File Provider domain. `eligibleForEmbeddings: true` is the flag that
puts the domain in the semantic pipeline. So the question is live: files are in scope. What is *not*
in scope is their content — sections 2 and 3.

**(O)** Same field for the other domains:

| Domain | `enabled` | `total-indexable-count` | `eligibleForEmbeddings` |
|---|---|---|---|
| `com.nextcloud.desktopclient.FileProviderExt` `3363…` | yes | 38,908 | true |
| `com.apple.CloudDocs.iCloudDriveFileProvider` `35FD…` | **no** | 4,010 (all pending) | true |
| `io.mountainduck.fileprovider` `F87F…` | yes | 406 | true |
| `io.mountainduck.fileprovider` `9E33…` | yes | 131 | true |

iCloud Drive's indexer reads `enabled: no` with its full 4,010 items pending — unexplained, flagged
below.

---

### 1b. Cross-check: the split is visible in the reports themselves

**(O)** Added 2026-08-13, from the report dated `2026-08-12T08:09:27Z`. Both third-party providers
appear in `Embedding` and in **no other pipeline**:

| pipeline | provider rows | all rows |
| --- | --- | --- |
| `Embedding` | `com.nextcloud.desktopclient` 98.94 % / 38,832 · `io.mountainduck` 98.59 % / 496 | 20 |
| `Keyphrase` | none | 9, all `com.apple.*` |
| `LSSR5EventsandordersUrgent` | none | 1 |
| `LSSR5EventsandordersBackground` | none | 3 |
| `LSSR5IdentificationdocumentsBackground` | none | 2 |

This is independent confirmation of the hard-coded allow-list found in the LSSR5 query strings
(section 5): third-party File Provider domains are absent from every LSSR5 pipeline, by bundle
identity, while being present in `Embedding`. Two providers from different vendors behaving
identically also rules out a Nextcloud-specific quirk.

It does **not** show that contents are read. A provider row near 99 % in `Embedding` means ~99 % of
the *donations the provider made* have been embedded, and section 3 establishes those donations were
built without reading a byte of file content.

---

## 2. Documented contract

**(D)** `NSFileProviderReplicatedExtension` requires `fetchContents(for:version:request:completionHandler:)`
— content is pulled only on demand. `NSFileProviderItem.contentPolicy` (`NSFileProviderContentPolicy`,
macOS 13+) selects when: `.inherited` (default; take the parent's), `.downloadLazily`,
`.downloadLazilyAndEvictOnRemoteUpdate`, `.downloadEagerlyAndKeepDownloaded`. The documented root
default is `.downloadLazily` with children `.inherited`.
Sources: [NSFileProviderContentPolicy discussion, Apple Developer Forums 756189](https://developer.apple.com/forums/thread/756189) ·
[Apriorit, working with File Provider on macOS](https://www.apriorit.com/dev-blog/730-mac-how-to-work-with-the-file-provider-for-macos).

**(D)** [TN3150 *Getting ready for dataless files*](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files)
tells developers to *avoid unnecessarily materialising* dataless files and to do content work off
the main thread. It is written for third-party apps, and says nothing about what Spotlight itself
does.

**Not documented anywhere I could find:** whether Spotlight/CoreSpotlight faults in dataless File
Provider files to index them. There is no `NSFileProviderSearchIndex` API. The indexing path
observed in section 3 (`fileproviderd` emitting `(CoreSpotlight)` signposts and calling
`CSSearchableIndex` on the provider's behalf) is **observed-not-documented**. Community reporting
says the opposite of materialisation — online-only files "can't be viewed using Quick Look, indexed
by Spotlight, or backed up"
([TidBITS, *Apple's File Provider Forces Mac Cloud Storage Changes*](https://tidbits.com/2023/03/10/apples-file-provider-forces-mac-cloud-storage-changes/)) —
which matches what the machine shows, but it is a blog post, not a contract.

---

## 3. Empirical: nothing was downloaded

### 3a. The indexed files are still dataless

**(O)** Sample every 80th path that Spotlight returns for the Nextcloud domain — i.e. only files
that are *definitely indexed* — and stat it:

```
$ NC=~/Library/CloudStorage/Nextcloud-<account>@<host>   # the provider's domain root
$ mdfind -onlyin "$NC" 'kMDItemContentTypeTree == "public.item"' > nc-mdfind.txt   # 36,291 items
$ awk 'NR%80==0' nc-mdfind.txt > sample.txt                                        # 453 paths
$ while IFS= read -r p; do stat -f '%Sf|%b|%z|%HT|%N' "$p"; done < sample.txt > s2.txt
$ awk -F'|' '{print $1" | "$4}' s2.txt | sort | uniq -c | sort -rn
 405 compressed,dataless | Regular File
  31 -                   | Directory
  17 compressed,dataless | Directory

$ awk -F'|' '$4=="Regular File"{print $2}' s2.txt | sort -n | uniq -c
 405 0                      # blocks allocated
$ awk -F'|' '$4=="Regular File"{s+=$3} END{print s}' s2.txt
6851217750                  # 6.85 GB logical, 0 bytes on disk
```

405 / 405 indexed regular files: `dataless`, zero allocated blocks. 6.85 GB of logical size costing
nothing. (`compressed` here is the `decmpfs` marker used to represent dataless files, not real
compression.)

### 3b. No content-derived attributes exist for those files

This is the discriminator. `kMDItemNumberOfPages` is produced by the PDF importer and **requires
reading the file**. It persists in the index after eviction, so its absence rules out
materialise-then-evict as well as materialise-and-keep.

**(O)**

```
$ mdfind -onlyin "$NC" 'kMDItemNumberOfPages > 0'            | wc -l
       0
$ mdfind -onlyin "$NC" 'kMDItemContentType == "com.adobe.pdf"' | wc -l
    1896
$ mdfind -onlyin ~/Documents 'kMDItemNumberOfPages > 0'        | wc -l    # control, local disk
    2949
$ mdfind -onlyin ~/Documents 'kMDItemContentType == "com.adobe.pdf"' | wc -l
    2949
```

1,896 PDFs indexed inside the provider domain, **0** with a page count. 2,949 PDFs on local disk,
**2,949** with one. **(I)** No PDF in the Nextcloud domain has ever had its bytes read by an
importer.

**(O)** A single 8.4 MB dataless PDF, flags checked before and after so `mdls` itself is ruled out
as a materialiser:

```
$ F="$NC/Archive/…/some-8.4MB-deck.pdf"
$ stat -f '%Sf blocks=%b size=%z' "$F"
compressed,dataless blocks=0 size=8423559
$ mdls "$F" | wc -l
      44
$ stat -f '%Sf blocks=%b size=%z' "$F"          # unchanged
compressed,dataless blocks=0 size=8423559
```

All 44 attributes are filesystem- or provider-level — `kMDItemFSName`, `kMDItemFSSize`,
`kMDItemContentType`, `kMDItemDisplayName`, dates, `kMDItemDocumentIdentifier`, plus the File
Provider pair `kMDItemIsUploaded = 1` / `kMDItemIsUploading = 0`. Absent: `kMDItemNumberOfPages`,
`kMDItemTitle`, `kMDItemAuthors`, `kMDItemTextContent`.

Caveat: `kMDItemTextContent` is not returned by `mdls` for *any* file, indexed or not — its absence
here proves nothing on its own. `kMDItemNumberOfPages` is the load-bearing one.

### 3c. Indexing and materialisation are different job classes

**(O)** 6 h of log, 11,985 lines:

```
$ /usr/bin/log show --last 6h \
    --predicate 'subsystem == "com.apple.FileProvider" OR process == "fileproviderd"' \
    --style compact > fp-log.txt
$ rg -o '\(CoreSpotlight\) [a-z-]+' fp-log.txt | sort | uniq -c | sort -rn
 317 (CoreSpotlight) report-donation-progress
 316 (CoreSpotlight) index-items
 316 (CoreSpotlight) end-index-batch
 277 (CoreSpotlight) fetch-attributes
   3 (CoreSpotlight) fetch-last-client-state
```

The indexing loop is `fetch-attributes` → `index-items` → `end-index-batch` →
`report-donation-progress`. **Attributes.** There is no content verb in it. A whole batch, verbatim:

```
12:27:16.317 A  fileproviderd[732:eb6d] (CoreSpotlight) fetch-attributes
12:27:16.439 Df fileproviderd[732:eb6d] [com.apple.FileProvider:default] [NOTICE] [spotlight] adding 2 and deleting 0 items state:<private> (in <private>)
12:27:16.439 A  fileproviderd[732:eb6d] (CoreSpotlight) end-index-batch
12:27:16.440 A  fileproviderd[732:eb6d] (CoreSpotlight) index-items
12:27:16.441 Df fileproviderd[732:eb6d] [com.apple.corespotlight:index] CSInlineDonation:<private>: Skipping donation (feature flag disabled)
12:27:16.443 Df fileproviderd[732:eb6d] [com.apple.FileProvider:default] [NOTICE] [spotlight] added 2 and deleted 0 items state:<private> in 0.004s (in <private>)
```

**(I)** `report-donation-progress` is very likely the feed for the completeness reports this app
reads — same cadence, same donor identity. Not verified.

**(O)** Materialisation is a separate job type and it is rare — 22 completed content fetches in the
same 6 h across all providers, against 38,908 + 4,010 + 406 + 131 indexable items:

```
$ rg -c 'done executing <FP[0-9]+ ✅  fetch-content' fp-log.txt
22
$ rg 'done executing <FP[0-9]+ ✅  fetch-content' fp-log.txt \
    | rg -o 'com\.apple\.FileProvider:[a-zA-Z0-9._]+' | sort | uniq -c
  15 com.apple.FileProvider:com.apple.CloudDocs.iCloudDriveFileProvider
   7 com.apple.FileProvider:com.nextcloud.desktopclient.FileProviderExt
$ rg -o 'why:[a-zA-Z|]+' fp-log.txt | sort | uniq -c | sort -rn | head -7
 964 why:itemChangedRemotely
 580 why:item
 360 why:materialization|itemChangedRemotely
 104 why:itemChangedRemotely|contentUpdate
  55 why:materialization|itemChangedRemotely|userRequest|contentUpdate
  25 why:deleted
  17 why:materialization|userRequest
```

Every `materialization` reason is paired with `itemChangedRemotely` and/or `userRequest`. None
carries an indexing reason. **(O)** The items fetched are packages and archives —
`.ofocus`, `.musiclibrary`, `.band`, `.xcodeproj`, `.tar`, `.enc` — 7 `pkg` and 15 `doc`.
**(I)** That is sync and package handling (a package must be materialised to be enumerated as a
directory), not indexing.

**(O)** Each provider's own counter agrees:

```
$ rg -n 'Materialize counters' fpdump.txt
7382:      + Materialize counters : 0 items with size 0
123278:      + Materialize counters : 0 items with size 0
124652:      + Materialize counters : 0 items with size 0
125226:      + Materialize counters : 0 items with size 0
```

### 3d. The LSSR5 pipelines exclude third-party providers outright

**(O)** `spotlightknowledged.updater` logs its LSSR5 query strings *unredacted*. Two distinct
strings in 3 h / 157,741 lines:

```
$ /usr/bin/log show --last 3h --predicate 'process == "spotlightknowledged.updater"' --style compact \
    | rg -o 'Running using query string .*' | sort -u
((kMDItemHTMLContentData=*||kMDItemTextContent=*||kMDItemTitle=*||kMDItemContentURL=*)
 &&FieldMatch(_kMDItemBundleID,"com.apple.mail","com.apple.mobilemail","com.apple.email.SearchIndexer",
   "com.apple.mobilecal","com.apple.CalendarUI","com.apple.MobileSMS",
   "com.apple.FileProvider.LocalStorage","com.apple.CloudDocs.iCloudDriveFileProvider")&&(true&&true))
 &&((*=*)&&_kMDItemUserActivityType!=*&&_kMDItemIsZombie!=*)

(FieldMatch(_kMDItemBundleID,"com.apple.mail","com.apple.mobilemail","com.apple.email.SearchIndexer",
   "com.apple.MobileSMS","com.apple.mobilenotes",
   "com.apple.FileProvider.LocalStorage","com.apple.CloudDocs.iCloudDriveFileProvider")
 &&((kMDItemContentTypeTree='com.apple.paper.doc.scan'||kMDItemContentTypeTree='com.adobe.pdf'
   ||kMDItemContentTypeTree='com.apple.paper.doc.pdf')&&true))
 &&((*=*)&&_kMDItemUserActivityType!=*&&_kMDItemIsZombie!=*)
```

Two things fall out. **(O)** The bundle allow-list is hard-coded and contains only
`com.apple.FileProvider.LocalStorage` and `com.apple.CloudDocs.iCloudDriveFileProvider` — no
third-party provider. Nextcloud and Mountain Duck items cannot reach LSSR5 at all. **(O)** These are
`kMDItem*` queries *against the existing index*: the pipeline selects items that already carry
`kMDItemTextContent`, it does not go extract it. A dataless file has no `kMDItemTextContent`, so it
fails the predicate and is skipped — consistent with, and an independent reason for, 3b.

**(O)** The Embedding pipeline works on donation IDs, not paths:

```
[com.apple.spotlightknowledge:JournalProcessingJob] [JournalProcessingJob.Embedding.Backlog.ClassC]
  [Donation 4760472 for <mask.hash: '/RZOqslpUC+qlHdVAQ/c4Q=='> in <mask.hash: 'T04Czcu…'>] Update did not …
[com.apple.spotlightknowledge:SpotlightKnowledgeEmbedding] [Document Embedding Generation]
  Start primary embedding generation for item bundleID com.apple.mail. 1 retries left.
```

Its only path-flavoured category, `[com.apple.spotlightindex:Path]`, emits nothing but
`Unlink <private>`. **(I)** The embedder consumes CoreSpotlight donations; for a File Provider
domain those donations were built from attributes.

---

## 4. Eviction

Moot, and therefore **unanswered**. Nothing was materialised for indexing, so no eviction was needed
and none was observed attributable to indexing.

**(O)** The Nextcloud domain sets no content policy at all — all 38,905 items in its dump section
read `cp:system`:

```
$ sed -n '7395,123270p' fpdump.txt | rg -o 'cp:[a-z]+\([a-zA-Z]+\)|cp:[a-zA-Z]+' | sort | uniq -c
38905 cp:system
```

**(D)** With no explicit `contentPolicy`, the documented default applies: lazy download, evictable.
`.downloadEagerlyAndKeepDownloaded` — the one policy that would pin content — appears only under
iCloud Drive's app-container tree (`cp:inherited(keepDownloaded)`, 1,577 nodes), never under
Nextcloud.

**(O)** `evictionUrgency` appears in `FS snapshot mutation … diffs:content|dataless|evictionUrgency`
lines, i.e. the system tracks an eviction priority per item, but the trigger was not identified.
**(I)** If indexing ever did materialise something, the default policy means it would be evictable
under pressure rather than pinned — inference from the documented default, not measured.

---

## Footguns hit while measuring this

- **`log` is a zsh builtin.** `log show --predicate '…'` in zsh fails with
  `(eval):log:1: too many arguments` and, inside a pipeline, produced an *empty result that looked
  like a clean negative*. Use `/usr/bin/log`. My first log query silently returned nothing.
- **`shuf` does not exist on macOS.** `shuf -n 400 … > sample.txt` left an empty file and exit 0
  further down the pipe. Use `awk 'NR%n==0'`.
- **Do not `find`/`lsof +D` a File Provider tree.** `find "$NC" -type f` and `lsof +D ~/Library/CloudStorage`
  both hit 5-minute timeouts driving provider enumeration and Nextcloud CPU. Sample from `mdfind`
  output instead, or stat individual paths. Worse, backgrounding one does not make it cheap: a
  `find` over three Nextcloud subtrees was still walking ~40 min later and had to be killed by pid.
  The cost is the provider's `readdir`, not the tool — note that in this shell `find` is a function
  wrapping `bfs`, so `/usr/bin/find` will behave no better.
- **`<private>` redaction is heavy but incomplete.** Item names are redacted with a
  first-char/count/last-char scheme (`n:"O{7}s.ofocus"`), item counts in `[spotlight] adding N` are
  clear, and the LSSR5 query strings are fully clear. The Embedding pipeline's item identities are
  `<mask.hash:>` and unrecoverable.
- **Everything here needed Full Disk Access** on the calling terminal — the report directory, and
  `fileproviderctl dump` for other apps' domains. An unprivileged bundle sees none of it (ADR-0004).
- `mdls` and `stat` did **not** materialise anything: flags were `compressed,dataless blocks=0`
  before and after in every check. Verified on the 8.4 MB PDF above.

---

## Verdict

**(I, strong)** Indexing a File Provider domain for the semantic index does **not** download file
contents. The provider donates attributes; `fileproviderd` forwards them to CoreSpotlight; the
Embedding pipeline embeds what it was given. A Nextcloud folder at 99.0 % Embedding completeness
across 38,700 items still occupies zero bytes on disk. The bandwidth/disk worry does not
materialise — literally.

Corollary worth stating: the flip side of this is that **file *contents* in a third-party File
Provider domain are not semantically indexed at all**. Apple Intelligence can find those files by
name, type, and date; it cannot search inside them while they are dataless. Nextcloud's 99.0 % is
99.0 % of a metadata-only job.

## Open questions

- iCloud Drive's indexer reports `enabled: no` with 4,010 / 4,010 items pending, yet
  `com.apple.CloudDocs.iCloudDriveFileProvider` is in both LSSR5 allow-lists. Whether iCloud Drive
  gets a privileged content path that third-party providers do not — **untested**, and the most
  likely place for this note's conclusion to be wrong.
- What happens on a file the user *has* materialised: does an importer then run and add
  `kMDItemNumberOfPages`, and does the Embedding pipeline pick up the richer donation? Untested;
  testing it means materialising a file, which was out of scope here.
- Whether `(CoreSpotlight) report-donation-progress` is what writes
  `completenessReport_*.plist`. Correlation only.
- `CSInlineDonation: Skipping donation (feature flag disabled)` fires on every index batch. What
  inline donation would do if enabled is unknown — a plausible future path to content indexing.
- Mountain Duck: 406 + 131 = 537 indexable vs 495 `eligibleItems` in a 23 h stale report. Not
  reconciled.
