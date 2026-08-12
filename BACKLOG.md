# Backlog — the only queue

Work the first unblocked item, top down. **Delete an item when it ships** — no "done" section;
`git log BACKLOG.md` is the record. `WL-N` numbers are never reused.

---

## Owed

### WL-5 — Widget is built and registered but has never rendered real numbers
- Blocked on the operator: the signature changed ad-hoc → Apple Development, so the Full Disk Access
  grant was invalidated (ADR-0004 predicted this). Until it is re-granted the app publishes a
  snapshot whose only content is the permission error, and the widget has nothing to draw.
- After the grant: add the widget from the gallery ("Semantic Index"), confirm small and medium
  render, and confirm the app-not-running footer by quitting the app for an hour.

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
