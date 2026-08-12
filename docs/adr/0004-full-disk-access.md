# ADR-0004: Ship unsandboxed, require Full Disk Access, and say so in the UI

> **TL;DR:** The report directory is TCC-protected with no entitlement that reaches it and no API to request access, so the app ships unsandboxed and detects the denial specifically, offering the Settings pane instead of a raw error. Accepted 2026-08-12.

- **Status**: Accepted
- **Date**: 2026-08-12
- **Deciders**: Justin

## Context

`~/Library/Metadata/CoreSpotlight/` is protected by TCC. This was not obvious during
reconnaissance: every shell read succeeded, because the terminal already held Full Disk Access. The
first launch of the built bundle failed with `NSFileReadNoPermissionError` on a directory that had
been readable all afternoon from a different process.

Full Disk Access has no request API. `AVCaptureDevice`-style prompts do not exist for it; the app
cannot trigger the grant, and there is no callback when the user grants it. The only path is System
Settings → Privacy & Security → Full Disk Access, adding the app by hand. macOS also does not
reliably deliver the new permission to an already-running process, so the app must be restarted
after the grant.

Sandboxing would make this worse, not better: no entitlement grants a sandboxed app access to
another process's metadata directory, so a sandboxed build cannot read the reports at all.

## Decision

Ship unsandboxed. Classify read failures at the loader: `NSFileReadNoPermissionError` / `EACCES` /
`EPERM` become `LoadError.permissionDenied`, distinct from `directoryMissing` for `ENOENT`. When the
store sees `permissionDenied` it sets `needsFullDiskAccess`, and the panel replaces its normal
content with an explanation, a button opening
`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`, and a button revealing
the app bundle in Finder so it can be dragged into the list.

## Consequences

The failure the user can actually fix is the one the UI explains, and the two failure modes stay
distinguishable — an absent directory (Apple Intelligence indexing never started) must not tell the
user to grant permissions that would not help. The distinction is pinned by two tests, one of which
creates a mode-`000` directory to exercise the real `EACCES` path.

The app cannot be distributed through the Mac App Store, which forbids unsandboxed apps. First-run
experience is a manual permission grant plus a restart, which is friction we cannot remove. The TCC
grant is keyed to the code signature: the ad-hoc signature from `make-app-bundle.sh` is stable across
rebuilds, but re-signing with a Developer ID identity will invalidate the grant and require the user
to remove and re-add the app.

## Alternatives considered

**Sandbox the app and ask the user to pick the directory via `NSOpenPanel`,** persisting a security-
scoped bookmark. Legitimate and App Store compatible. Rejected: it makes the user navigate to a
hidden `~/Library` path on first run, which is worse friction than the Settings pane, and
security-scoped bookmarks to a system-managed directory are fragile across OS updates.

**Show the raw `NSError` and let the user work it out.** What the first build did. Rejected on sight:
"you don't have permission to view it" names neither the cause nor the fix, and the fix is three
clicks away behind a URL the app can open itself.
