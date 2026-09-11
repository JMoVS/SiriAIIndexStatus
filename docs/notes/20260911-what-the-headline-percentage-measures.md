# What the headline percentage actually measures

Measured 2026-09-11 against the live reports (`reportDate` 2026-09-10T07:58) and the 16 checkpoints
in `history.json` (2026-08-25 → 09-10). Prompted by the operator: "always around 50%, never really
increasing".

## The arithmetic is right

`all`.`pipelineCompleteness` is exactly the item-weighted mean of the per-app rows, to six decimals:

| Pipeline | `all` | Σ(app.completeness × app.eligible) / Σ app.eligible |
|---|---|---|
| `Embedding` | 0.472750 | 0.472750 |
| `Keyphrase` | 0.154307 | 0.154307 |

`all`.`eligibleItems` equals the sum of the app rows' (205,341 and 110,915). So the parse, ADR-0003's
"`all` is not a sibling" rule, and the aggregation all hold. The number on screen is the number Apple
wrote.

## But it answers a question nobody asked

`Embedding`, 2026-09-10, by share of the denominator:

| Bundle | Eligible | Share | Complete |
|---|---|---|---|
| `com.apple.mail` | 118,508 | 57.7% | 32.6% |
| `com.nextcloud.desktopclient` | 36,140 | 17.6% | 60.4% |
| `com.apple.CalendarUI` | 24,915 | 12.1% | 99.0% |
| `com.apple.helpviewer` | 13,069 | 6.4% | 2.2% |
| everything else (18 rows) | 12,709 | 6.2% | mixed |

Three donors are 87% of the headline. Of those three:

- **Mail is the only one doing work.** 27.2% → 32.6% over the 17 days of history, on a denominator
  that moved 118,550 → 118,508 (flat). That is ~6,400 items genuinely embedded — real progress,
  worth ~3 points of the headline, and invisible underneath the next item.
- **Nextcloud is noise.** Its eligible set over the same window: 40,485 → 3,286 → 409 → 23,669 →
  36,140. The headline followed it: 52.6% → 39.9% → 52.7% → 47.3%. No embedding work is in any of
  those swings (this is WL-12's mechanism, now with the donor named). It is also metadata-only —
  content of third-party File Provider files is never read (WL-8), so its 60.4% is not the same
  quantity as Mail's 32.6%.
- **Help Viewer is a floor.** 13,069 items pinned at 2.2% for the entire window. 6.4% of the
  denominator that will never complete, subtracted from the headline forever.

So "around 50%, never increasing" is an accurate reading of a statistic whose movement is dominated
by a third-party provider's bookkeeping and whose ceiling is set by macOS help documents.

## Apple ships a second number, and it disagrees

`pipelineCompletenessHeuristicScore` is **not** equal to `pipelineCompleteness` — the earlier note
said it was, on a sample where it happened to be. Live:

| Pipeline / bundle | `pipelineCompleteness` | `…HeuristicScore` |
|---|---|---|
| `Embedding` / `all` | 0.4728 | 0.6003 |
| `Keyphrase` / `all` | 0.1543 | 0.3785 |
| `LSSR5EventsandordersBackground` / `com.apple.MobileSMS` | 0.0222 | 0.2547 |
| `LSSR5IdentificationdocumentsBackground` / `all` | 0.0231 | 0.5115 |

The `all` row's heuristic score is neither the item-weighted nor the unweighted mean of the app
rows' (Embedding: 0.6003 vs 0.4513 weighted, 0.7115 unweighted). Apple computes it some other way;
we cannot reproduce it from what the file contains.

## The bucket fields are populated after all

`pipelineCompleteness{FirstTime,Second,Third}Bucket` are `$null` on most rows but populated on the
big, slow ones — the earlier note called them unpopulated in every observed row:

| Pipeline / bundle | First | Second | Third | completeness |
|---|---|---|---|---|
| `Embedding` / `com.apple.mail` | 0.2639 | 0.5282 | 0.3257 | 0.3265 |
| `Embedding` / `com.apple.CalendarUI` | 0.8333 | 0.8980 | 0.9901 | 0.9898 |
| `Embedding` / `com.apple.MobileSMS` | 0.1333 | 0.8920 | 0.9992 | 0.9957 |
| `LSSR5EventsandordersBackground` / `com.apple.MobileSMS` | 0.2000 | 0.6095 | 0.0093 | 0.0222 |

Third bucket tracks `pipelineCompleteness` closely but never exactly. Consistent with age or
priority cohorts of the eligible set, with the heuristic score weighting them — the Messages row
is the tell: 0.0093 done in the third bucket, 0.61 in the second, and Apple scores the pipeline
0.2547 rather than 0.0222. Untested as a theory; the buckets are decoded now so it can be watched.

## What this does not say

Nothing here shows the index is broken. It shows the headline cannot distinguish "Mail embedded
6,400 more messages" from "Nextcloud re-enumerated its share". Fixing that is a display question —
see the backlog.
