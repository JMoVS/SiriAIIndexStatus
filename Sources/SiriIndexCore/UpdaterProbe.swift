import Foundation

/// Is `spotlightknowledged.updater` — the process that actually writes the embedding stores —
/// currently running?
///
/// `pgrep` rather than a framework call: there is no public API for daemon liveness, and the
/// daemon is launch-on-demand, so absence is normal rather than an error (ADR-0002).
public enum UpdaterProbe {
    public static let processName = "spotlightknowledged.updater"

    public static func isRunning(named name: String = UpdaterProbe.processName) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        // -x: exact name match, so `spotlightknowledged` alone does not satisfy the probe.
        process.arguments = ["-x", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            // Sandboxed or pgrep missing — report "unknown" as not-running rather than crashing.
            return false
        }
    }
}
