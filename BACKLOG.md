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
