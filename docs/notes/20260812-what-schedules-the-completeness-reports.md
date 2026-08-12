# What schedules the completeness reports — and can we trigger one?

**Measured 2026-08-12, macOS 26.6.1 (build 25G76).** Short answer: no, not from userspace. The reports
are written by a background task on a 24 h repeat that **only runs on external power**.

## The job

`/System/Library/LaunchAgents/com.apple.spotlightknowledged.updater.plist` — the whole schedule is in
the `LaunchEvents` dictionary:

```
"LaunchEvents" => {
  "com.apple.bg.system.task" => {
    "com.apple.corespotlight.knowledge.report" => {
      "#IfFeatureFlagEnabled" => "SpotlightKnowledge/MetricsJobRefactor"
      "#Then" => {
        "Priority" => "Utility"
        "RepeatingTask" => { "Interval" => 86400 }
        "RequiresExternalPower" => true
        "RequiresNetworkConnectivity" => false
        "RequiresProtectionClass" => "C"
      }
    }
  }
}
"ProgramArguments" => [ "/usr/libexec/spotlightknowledged.updater", "-u" ]
```

Four things this settles:

- **86400 s.** "Roughly daily" (ADR-0002) is exactly daily, by declaration rather than by inference.
- **`RequiresExternalPower` = true.** On battery the report does not refresh *at all*. A reading can
  therefore be arbitrarily stale on an unplugged laptop while indexing itself carries on — the app's
  numbers going nowhere for three days says nothing about the index.
- **`RequiresProtectionClass` = "C"** — the machine must have been unlocked since boot.
- The criteria sit behind feature flag `SpotlightKnowledge/MetricsJobRefactor`, which
  `/System/Library/FeatureFlags/Domain/SpotlightKnowledge.plist` reports as
  `DevelopmentPhase = FeatureComplete`.

`Priority = Utility` also means the scheduler is free to defer it under load or thermal pressure, so
86400 s is a floor on the interval, not a guarantee.

## Trigger attempts, all failed

| Attempt | Result |
| --- | --- |
| `launchctl kickstart -k gui/501/com.apple.spotlightknowledged.updater` | `150: Operation not permitted while System Integrity Protection is engaged` |
| `/usr/libexec/spotlightknowledged.updater -u` run directly | exits in under 5 s, no output, no report written — it needs the launchd/XPC context, and the `com.apple.spotlightknowledged` Mach service is already held by the running instance (pid 815) |
| A CLI for the background-task scheduler | none ships: no `xpcctl`, `dasdiagnose`, `duetctl` or `bgtaskctl`. `/usr/libexec/dasd` and `coreduetd` exist but expose nothing callable |
| `launchctl` subcommands for activities | only `kickstart` and `blame` are relevant, and `kickstart` is the SIP-blocked path above |

`launchctl blame gui/501/com.apple.spotlightknowledged.updater` returns `ipc (mach)` — the updater
is usually already running because something else is talking to it, which is why `kickstart` without
`-k` is a no-op anyway.

## What we can rely on instead

The file mtime equals the `reportDate` inside the archive exactly (checked: both
`2026-08-11 20:04:23` local, `12:04:23Z` — the machine is UTC+8). So the on-disk timestamp is a
truthful freshness signal and the app does not need to decode a report to know how old it is.

Practically: plug in, stay unlocked, wait for the next 24 h window. The report observed at
`2026-08-11 20:04` implies the next one lands around `2026-08-12 20:04` local, subject to `Utility`
deferral.

## Consequence for the app

Staleness is not one condition but two, and only the app can tell them apart:

- On AC and older than ~26 h ⇒ the scheduler deferred it, or indexing has nothing new to report.
- On battery ⇒ expected; the number is frozen by design and should not be read as stalled indexing.

Filed as WL-7. This also sharpens WL-2: the freshness signal should say *why* a figure is old, not
merely that it is.
