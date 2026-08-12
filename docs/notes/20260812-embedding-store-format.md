# Can we read the embeddings themselves?

**Measured 2026-08-12, macOS 26.6.1 (build 25G76).** Partly. The stores are readable with Full Disk
Access and their headers give useful counts. The vectors are not readable without reverse-
engineering an undocumented format, which has not been done.

## What is on disk

`~/Library/Metadata/CoreSpotlight/SpotlightKnowledgeEvents/index.V2/embedding_cache/<n>/<n>/<client>/`

| store | bytes | records | last written |
| --- | ---: | ---: | --- |
| `4/cs_pc_c/embedding_store.db` | 220,565,504 | **100,000** | 2026-08-05 09:38 |
| `10/4/cs_pc_c/embedding_store.db` | 36,622,336 | 23,470 | 2026-08-12 14:18 |
| `4/cs_pc_a/embedding_store.db` | 20,480 | 0 | 2025-03-18 05:38 |
| `10/4/cs_mail/embedding_store.db` | 20,480 | 0 | 2026-08-07 00:37 |

Each `.db` has a `.embedding_store.db` shadow of identical size beside it, plus six
`embedding_store.dbStr-N.map.{header,header.shadow,buckets,offsets,data}` sidecars.

Two things stand out, both **inference, not established**:

- `4/cs_pc_c` stopped at exactly **100,000** records on 2026-08-05 and has not been written since,
  while `10/4/cs_pc_c` started and is being written today. A round number that stops dead reads like
  a per-store cap with a new generation rolled over, not a coincidence.
- `cs_mail`'s store holds **zero** records, though the Embedding pipeline reports substantial mail
  progress. Either mail embeddings live somewhere else (`cs_pc_c` — "personal context"? — is the
  only store with content), or the per-client directory is not what its name suggests.

## Format

```
00000000: 3874 7364 4100 0700 0000 0000 0c00 0000   8tsd...........
00000010: 0000 0000 a086 0100 0000 0000 0100 0000   ......100000....
00000020: 0000 0000 0010 0000 0080 0300 0040 0000   ......4096......
```

- Magic `8tsd`. 4 KB pages (`hdr[8]`); record count at `hdr[4]`; `hdr[0]` is 458753 on three stores
  and 458817 on the full one.
- Sidecar maps carry their own magic `DataP` and **plaintext keys** — `embedding_store.dbStr-1.map.data`
  begins with the literal `embedding_info`. So the maps are string-keyed dictionaries; the payload
  is not.
- Not SQLite, not a plist, not an `NSKeyedArchiver` archive.

## Two failed attempts to find the vectors, recorded so nobody repeats them

1. **Scanning for "float32-plausible" 4 KB windows** — 25 windows in a 3 MB slice scored >99% of
   values within ±1.0. All of them were **denormals**: the values at `0xe000` print as `0.0000`,
   `-0.0000`, and a norm test across dims 64…1024 returned norms of 0.0000 for everything below 768
   and 4e8 for 1024. "In range" is not evidence when the range test admits zero.
2. **Assuming a fixed record stride.** 220,565,504 / 100,000 = 2205.65 and 36,622,336 / 23,470 =
   1560.4 — not integral, and not equal to each other, so records are not laid out back to back at a
   fixed size. Both files are exact multiples of the 4 KB page, so slack is per page.

A serious attempt would need the record layout from the sidecar offset maps rather than guessing at
the payload, and probably `Embedding.framework` / `spotlightknowledged` symbols. Quantised int8 is
the obvious next hypothesis given the sizes; untested.

## Privacy observation, since it comes up

A 3 MB sample of the 220 MB store yields 3,936 printable runs of ≥6 characters, **none** of them
words — all high-entropy noise. The indexed source text is not sitting in this file in the clear.
The plaintext that does exist is in the sidecar maps and is schema, not content (`embedding_info`).

## The supported route

CoreSpotlight ships `CSUserQuery`, which queries this index semantically and returns items. That
answers "what did the indexer actually produce" at the level anyone needs, without decoding
anything. Filed as WL-10 — it would also make the app demonstrate that the percentage means
something, which is a better answer to "is it working" than a number is.
