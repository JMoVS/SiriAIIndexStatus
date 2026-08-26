import Foundation

/// One reading of the reports, kept so the next one has something to be compared against.
///
/// The reports themselves carry no history: macOS overwrites
/// `completenessReport_<pipeline>.plist` in place, so yesterday's figures are gone the moment the
/// daemon writes today's. "How much was indexed since the last report" is therefore only
/// answerable by an app that was running to see the previous checkpoint — this is that record.
public struct IndexObservation: Codable, Sendable, Hashable {
    /// When this app read the reports. Not when the reports were written — see `status.reportDate`.
    public let recordedAt: Date
    public let status: IndexStatus

    public init(recordedAt: Date, status: IndexStatus) {
        self.recordedAt = recordedAt
        self.status = status
    }
}

/// Append-only log of checkpoints, one entry per distinct report date.
public enum HistoryStore {
    /// Roughly two months of daily checkpoints. The file is a few KB per entry.
    public static let maximumObservations = 60

    /// The App Group container when the bundle has one, otherwise Application Support.
    ///
    /// The container is preferred so the widget can eventually read the same history (ADR-0005),
    /// but an unsigned local build has no container and losing the whole feature over that would
    /// be worse than keeping the file somewhere only the app can see.
    public static func defaultURL() throws -> URL {
        if let container = SnapshotStore.containerURL {
            return container.appending(path: "history.json")
        }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "de.justinscholz.SiriAIIndexStatus", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appending(path: "history.json")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Missing file means "nothing recorded yet", which is the normal state on first launch and
    /// not an error worth surfacing.
    public static func load(from url: URL? = nil) throws -> [IndexObservation] {
        let url = try url ?? defaultURL()
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        return try decoder.decode([IndexObservation].self, from: Data(contentsOf: url))
    }

    public static func save(_ history: [IndexObservation], to url: URL? = nil) throws {
        try encoder.encode(history).write(to: url ?? defaultURL(), options: .atomic)
    }

    /// Fold a fresh reading into the log. Pure, so the rules are testable without a disk.
    ///
    /// The app polls every ten minutes but the reports move about once a day, so almost every
    /// reading is a re-read of a checkpoint already recorded. Those replace the existing entry
    /// rather than appending: appending would fill the log with identical copies and leave the
    /// comparison with nothing older to look at.
    public static func recording(
        _ status: IndexStatus,
        at now: Date,
        into history: [IndexObservation]
    ) -> [IndexObservation] {
        // A reading with no report date cannot be placed in time, so it cannot be compared with.
        guard let reportDate = status.reportDate, !status.pipelines.isEmpty else { return history }

        var history = history
        let observation = IndexObservation(recordedAt: now, status: status)

        if let last = history.last, let previous = last.status.reportDate,
           isSameCheckpoint(previous, reportDate) {
            history[history.count - 1] = observation
        } else {
            history.append(observation)
        }

        if history.count > maximumObservations {
            history.removeFirst(history.count - maximumObservations)
        }
        return history
    }

    /// Report dates survive a round trip through the log only to the second: ISO 8601 carries no
    /// fractional part, so a date read back off disk is never `==` the one just decoded from the
    /// plist (`…883.489249` becomes `…883.0`). Comparing them exactly made every ten-minute poll
    /// look like a new checkpoint, and the log filled with copies of one reading.
    public static func isSameCheckpoint(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 1
    }

    @discardableResult
    public static func record(
        _ status: IndexStatus,
        at now: Date = Date(),
        in url: URL? = nil
    ) throws -> [IndexObservation] {
        let url = try url ?? defaultURL()
        let history = recording(status, at: now, into: try load(from: url))
        try save(history, to: url)
        return history
    }
}
