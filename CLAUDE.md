# SiriAIIndexStatus

macOS menu bar app (+ desktop widget) showing how far along Apple Intelligence's on-device semantic
index is. macOS 26 builds this index but exposes no UI for it; the app reads the completeness
reports CoreSpotlight already writes to disk.

**Status:** menu bar app works end to end. Widget scaffolded, not yet bundled — see `BACKLOG.md`.

**Mode: DEV, low risk.** Read-only observer: no writes outside its own container, nothing on a data
path, no network. A bug costs a wrong percentage on screen. Optimize for iteration speed. Rigor is
deliberately lighter than a production data-path project — no probe ledger, no mandatory worktrees,
no dual review.

## Response style

Chat replies + subagent summaries (ADRs/notes stay precise — compress wording, never content):

- Telegram style: fragments over sentences · `⇒`/`→`/`·` over connective prose · numbers + names
  over description · no analogies, no scene-setting.
- First sentence = what happened / what you found. Status reports ≤ 10 lines, shape
  **did / found / next**, no headers.
- Never quote CLAUDE.md/ADRs/backlog back to the operator — cite by name (`ADR-0002`), zero excerpts.
- No build-and-reversal rhetoric ("Sounds safe. It isn't."). Facts once, flat.
- Never assert own honesty/candor ("honest caveat", "frankly", "to be clear") — state the caveat
  itself, unadorned. Intent banned, not just the words.
- Reversible work: do → verify → report. Never end "want X or Y?" — pick one, one line why. Ask only
  if irreversible or scope change.
- Unverified = "untested", one word. Self-chosen detour = one flag line.

## Docs

- `BACKLOG.md` — the only queue; read first. Delete items when done (`git log` is the record).
- `docs/adr/` — decisions worth not re-litigating. Cite `ADR-NNNN`. `/new-adr` scaffolds.
- `docs/notes/` — what we measured about Apple's private index surfaces. Evidence lives here.
- `plans/` — only for a slice big enough to need one. Most work here does not.
- `README.md` — how to build, install, and grant Full Disk Access.

## Workflow

- Start and end at `BACKLOG.md`. Append items as work surfaces; delete on ship.
- Work items end to end, no permission pauses. Stop only for scope changes or operator-only steps
  (granting TCC, signing with a real identity).
- `swift build` / `swift test` before reporting done. Both are fast (~4 s / ~10 s).
- UI change ⇒ rebuild the bundle and relaunch, don't claim it works from a compile:
  `Scripts/make-app-bundle.sh release && open build/SiriAIIndexStatus.app`.
- Subagents optional. `macos-platform-expert` for "how does this Apple private surface behave"
  questions; everything else the main loop handles directly.

## Conventions

- Swift 6 language mode, SwiftPM, Apple frameworks only — no third-party deps (ADR-0001).
- Parsing and aggregation live in `SiriIndexCore` so the app and the widget cannot disagree about a
  number. UI targets hold no arithmetic.
- Anything derived from a private Apple format gets a test with the real observed values in it. The
  format is Apple's to change; a test is how we find out that it did.
- Never swallow errors — surface them in the UI or log via `os.Logger`. A failed read keeps the last
  good snapshot on screen rather than blanking it.
- Design questions → ADRs, not source comments.
- `rg`, not `grep`.

## Key facts (measured 2026-08-12, macOS 26.6.1 / build 25G76)

- Reports: `~/Library/Metadata/CoreSpotlight/PipelineCompletenessReporting/completenessReport_*.plist`.
  `NSKeyedArchiver` archives of `CSPipelineCompletenessReport`, decoded via class substitution
  (ADR-0002). Refreshed roughly daily — checkpoints, not a live feed.
- Five pipelines observed: `Embedding` · `Keyphrase` · `LSSR5EventsandordersUrgent` ·
  `LSSR5EventsandordersBackground` · `LSSR5IdentificationdocumentsBackground`.
- The `all` row is the pipeline's aggregate, **not** a sibling of the per-app rows. Summing it with
  them double-counts every item (ADR-0003).
- `spotlightknowledged.updater` does the work — verified holding `embedding_cache/…/cs_mail/
  embedding_store.db` open. `siriknowledged` and `intelligencecontextd` are consumers.
  `knowledge-agent`/`knowledgeC.db` is the unrelated legacy Duet usage DB.
- `pgrep -x spotlightknowledged.updater` matches despite the 27-char name — no `p_comm` truncation.
- The report directory is TCC-protected: the app needs Full Disk Access, granted by hand, with no
  API to request it (ADR-0004).
