import Foundation
import Observation
import SiriIndexCore
import WidgetKit
import os

/// Owns the current snapshot and the refresh cadence.
///
/// Reports refresh roughly daily, so polling is deliberately slow (ADR-0002); the menu also
/// refreshes on open so an explicit look is never stale-by-a-poll-interval.
@MainActor
@Observable
public final class StatusStore {
    public private(set) var status: IndexStatus = .empty
    /// Progress since each pipeline's previous report, or nil until a second checkpoint has been
    /// seen. The reports themselves keep no history — the app has to have been running for the
    /// earlier one (`HistoryStore`).
    public private(set) var delta: IndexDelta?
    public private(set) var lastError: String?
    /// Set when the report directory exists but TCC blocks the read — the one failure the user
    /// can actually fix, so the UI offers the Settings pane rather than the raw message.
    public private(set) var needsFullDiskAccess = false
    public private(set) var lastRefresh: Date?
    public private(set) var isRefreshing = false

    private let directory: URL
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?
    private var lastPublishedStatus: IndexStatus?
    private var lastPublishedFailure: String?
    private var lastPublishedDelta: IndexDelta?
    private let log = Logger(subsystem: "de.justinscholz.SiriAIIndexStatus", category: "status")

    /// One refresh's worth of work, carried back from the background task in one piece.
    private struct Reading: Sendable {
        let status: IndexStatus
        let delta: IndexDelta?
        let historyError: String?
    }

    public init(
        directory: URL = ReportLoader.defaultDirectory,
        pollInterval: Duration = .seconds(600)
    ) {
        self.directory = directory
        self.pollInterval = pollInterval
    }

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let directory = self.directory
        let result = await Task.detached(priority: .utility) { () -> Result<Reading, Error> in
            do {
                let rows = try ReportLoader.loadAll(from: directory)
                let running = UpdaterProbe.isRunning()
                let status = IndexStatusBuilder.build(from: rows, updaterRunning: running)
                // Recording happens off the main actor with the read that produced it: the log is
                // what makes the *next* reading comparable, so a skipped write costs a whole day.
                var delta: IndexDelta?
                var historyError: String?
                do {
                    delta = IndexDelta.latest(in: try HistoryStore.record(status))
                } catch {
                    historyError = error.localizedDescription
                }
                return .success(Reading(status: status, delta: delta, historyError: historyError))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let reading):
            self.status = reading.status
            self.delta = reading.delta
            self.lastError = nil
            self.needsFullDiskAccess = false
            // A broken history costs the comparison, not the reading — the percentages on screen
            // are still correct, so this logs rather than taking over the UI.
            if let historyError = reading.historyError {
                log.error("history record failed: \(historyError, privacy: .public)")
            }
        case .failure(let error):
            // Keep the last good snapshot on screen — a transient read failure should not blank it.
            self.lastError = error.localizedDescription
            self.needsFullDiskAccess = (error as? ReportLoader.LoadError)?.isPermissionDenied ?? false
            log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
        }
        self.lastRefresh = Date()
        publishSnapshot()
    }

    /// The widget is sandboxed and cannot read the reports itself, so the app is its only source
    /// (ADR-0005). Failures here never touch the menu bar UI — the app's own display is fine; it is
    /// only the widget that goes stale, so this logs and moves on.
    private func publishSnapshot() {
        let snapshot = SnapshotStore.Snapshot(
            status: status, capturedAt: Date(), failure: lastError, delta: delta
        )
        do {
            // Always written, so `capturedAt` stays fresh and the widget can tell "nothing changed"
            // apart from "the app stopped running".
            try SnapshotStore.write(snapshot)
            // Reloads are rationed, though: the timeline only needs redrawing when a number moved,
            // and reports move about daily.
            let changed = (status, lastError, delta) != (lastPublishedStatus, lastPublishedFailure, lastPublishedDelta)
            lastPublishedStatus = status
            lastPublishedFailure = lastError
            lastPublishedDelta = delta
            if changed { WidgetCenter.shared.reloadAllTimelines() }
        } catch {
            log.error("snapshot publish failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
