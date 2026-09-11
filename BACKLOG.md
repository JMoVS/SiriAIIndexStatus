# Backlog — the only queue

Work the first unblocked item, top down. **Delete an item when it ships** — no "done" section;
`git log BACKLOG.md` is the record. `WL-N` numbers are never reused.

---

## Owed

### WL-13 — Say what the headline is made of, beyond the top three donors
- Shipped: each pipeline now shows where its missing percentage sits — the three donors holding
  most of it, what each withholds in points, and whether each one indexed, resized its total, or
  did nothing. Verified against the live reports: Embedding's missing 52.7 reads Mail 38.9 ·
  Nextcloud 7.0 · Help Viewer 6.2 · 19 others 0.7. Evidence for why this was needed:
  `docs/notes/20260911-what-the-headline-percentage-measures.md`.
- Still owed, both needing a judgement call rather than more arithmetic:
  - **Apple's own score.** `pipelineCompletenessHeuristicScore` reads 0.6003 where we print 0.4728,
    and the `all` row's cannot be recomputed from the file. Showing it means showing two
    percentages that disagree, so it needs wording that says which is which and why.
  - **A headline that ignores stuck denominators.** `stalledShare` already measures the dead weight
    (Help Viewer: 6.4% of Embedding, motionless for 17 days). Excluding it needs a rule for "stuck"
    that is not a Nextcloud/Help Viewer special case — probably "no movement across N reports",
    which means reading `history.json` rather than one delta.

### WL-6 — Widget states other than "everything works" are unverified
- Medium renders real numbers. Still never seen on screen: the small family, the "App not running"
  footer (needs the app quit for an hour), the failure text after a snapshot write error, and the
  new progress line (`+7,244 in 1d`), which needs two checkpoints before it draws at all.
- Cheap once the layout settles; the medium layout was already clipping its title and age line
  before anyone looked at it, which is the argument for looking at the rest.

### WL-7 — Say *why* a reading is old, not just that it is
- The report job requires external power (`RequiresExternalPower`, measured — see
  `docs/notes/20260812-what-schedules-the-completeness-reports.md`). On battery the figures are
  frozen by design, and the app currently presents that identically to a stalled index.
- Read the power source (`IOPSCopyPowerSourcesInfo`); when on battery and the report is older than
  ~26 h, say "waiting for power" rather than showing an unexplained old timestamp.
- Do this with WL-2 — same line of UI, and the reason is the part that carries information.

### WL-8 — Third-party File Provider percentages mean less than they look like
- Measured: content of third-party File Provider files is never read. Nextcloud sits at 99.0% of a
  *metadata-only* job — 1,896 indexed PDFs, zero with `kMDItemNumberOfPages`, all still dataless.
  The LSSR5 bundle allow-list contains only Apple's own local and iCloud Drive providers. Evidence:
  `docs/notes/20260812-fileprovider-materialization.md`.
- So an app row near 100% can mean "fully indexed" or "fully indexed as far as filenames go", and
  the panel gives the operator no way to tell.
- Cheapest honest fix: mark rows for known File Provider bundle IDs, footnoted once. Deciding what
  the mark says needs the iCloud Drive question below settled first.

### WL-9 — Does iCloud Drive get a privileged content path?
- The one thing that could overturn WL-8: iCloud Drive's indexer reports `enabled: no` with
  4,010/4,010 pending, yet appears in both LSSR5 allow-lists. If it does read content where
  third-party providers cannot, the two are not the same case and WL-8's wording is wrong.

### WL-10 — Prove the index works, rather than only reporting a percentage
- `CSUserQuery` runs a semantic query against the index CoreSpotlight built. A "try a search" field
  in the panel would show whether 48.7% of Embedding actually retrieves anything sensible — a
  question the percentage cannot answer.
- Also the only supported way to see what the indexer produced: the embedding stores themselves are
  an undocumented binary format (`docs/notes/20260812-embedding-store-format.md`).
- Check first whether `CSUserQuery` semantic ranking needs an entitlement; if it does, this dies.

### WL-11 — The embedding store looks like it rolled over at exactly 100,000
- `4/cs_pc_c` stopped at 100,000 records on 2026-08-05 and `10/4/cs_pc_c` has been growing since.
  If that is a per-store cap rather than a coincidence, the completeness percentage may be measured
  against something that resets, and "100%" would not mean what the panel implies.
- Cheap test: watch whether `10/4/cs_pc_c` also stops at 100,000. It is at 23,470.

### WL-12 — A partial recompute still reads as a regression
- The denominator-churn half shipped with WL-13: donors whose eligible set moved further than their
  indexed count now read `total +12,404` rather than a green item count, and a pipeline where that
  dominates says so outright. What remains is the sharper case below.
- 2026-09-04's report recomputes several pipelines from partial state (Keyphrase/Mail
  49,483 → 9,732 → 49,079 the next day). A single-step delta calls the middle reading a −39k
  regression, and no per-donor classification helps: the donor really did lose 39k indexed items
  for one checkpoint. Detecting it needs the checkpoint *after* it, i.e. `history.json`, not the
  one-step delta.
- Historical context, measured over 11 checkpoints (2026-08-25 → 09-05): Embedding fell
  52.1% → 39.9% on 08-31 and recovered to 52.7% on 09-04 purely because Nextcloud's eligible set
  went 40,485 → 409 → 23,670 items. No embedding work is in that swing; the panel showed it as
  −40,442 then +25,587.

### WL-2 — Report freshness is invisible until you open the panel
- Reports refresh roughly daily, so a menu bar reading can be a day stale with no signal.
- Show staleness in the menu bar title itself once it exceeds ~36 h (dim the text, or append `?`).

### WL-3 — Poll instead of watching
- `StatusStore` polls every 10 min. The directory changes at most daily ⇒ ~140 pointless reads/day.
- Replace with a `DispatchSource` file-system watch on the report directory, keeping a slow timer as
  a backstop. Small win; do it when touching the store for another reason.

### WL-4 — No launch-at-login
- `SMAppService.mainApp.register()` behind a toggle in the panel. Needs the bundle to live somewhere
  stable (`/Applications`), so pair it with a real install step in `README.md`.

---

## Parked (not blocking anything)

- **Per-app drill-down beyond 8 rows.** The panel caps laggards at 8. Fine until a pipeline has more
  interesting apps than that.
- **Historical trend as a chart.** The one-step delta ships (ADR-0006): each pipeline shows what it
  got through since its own previous report. The log behind it holds 60 checkpoints, so a sparkline
  over weeks is now only a view away — worth it if the single-step figure turns out to be too noisy
  to read a trend from.
- **`mdutil` / daemon-health surface.** Currently only "updater running / idle". Deeper health
  (last journal job, items processed) is only in `log stream`, mostly `<private>`.
- **Localization.** German UI, given the operator's locale. Strings are currently inline English.
- **Panel height on a short screen.** The list now scrolls, capped at the screen's visible height
  less 200 points of chrome, so the window stops at 895 points here whatever is expanded. On a
  display under ~480 points tall the floor of 280 wins and the panel would still overhang; nobody
  has such a screen, so this is noted rather than handled.
- **Seeing the panel.** `SIIS_RENDER_PANEL=<path>` renders it to a PNG and exits, and
  `SIIS_RENDER_EXPANDED=Embedding,Keyphrase` opens pipelines — both honoured by the live app too.
  The renderer makes one layout pass, so it draws the list at full length and cannot show the
  scroll cap; measuring that means reading the running window's size. `ProgressView` and
  `TextField` also come out as blank blocks. Neither is a defect in the panel.
