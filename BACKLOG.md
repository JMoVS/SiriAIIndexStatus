# Backlog — the only queue

Work the first unblocked item, top down. **Delete an item when it ships** — no "done" section;
`git log BACKLOG.md` is the record. `WL-N` numbers are never reused.

---

## Owed

### WL-6 — Widget states other than "everything works" are unverified
- Medium renders real numbers. Still never seen on screen: the small family, the "App not running"
  footer (needs the app quit for an hour), and the failure text after a snapshot write error.
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
- **Historical trend.** Sampling the reports over time would show whether indexing is actually
  progressing or wedged — the question the operator asked first. Needs its own store and a chart;
  worth it only if indexing turns out to stall.
- **`mdutil` / daemon-health surface.** Currently only "updater running / idle". Deeper health
  (last journal job, items processed) is only in `log stream`, mostly `<private>`.
- **Localization.** German UI, given the operator's locale. Strings are currently inline English.
