import Foundation

/// The hand-off between the menu bar app and the widget extension.
///
/// The app is unsandboxed and holds Full Disk Access, so it can read the report directory
/// (ADR-0004). The widget extension is sandboxed and gets no TCC grant of its own, so it cannot —
/// it only ever reads the JSON the app leaves in the shared App Group container (ADR-0005).
///
/// This is also why the snapshot carries `failure`: when the app's read breaks, the widget has no
/// way to discover that itself, and no way to open Settings to fix it. The most it can do is say
/// why its numbers stopped moving.
public enum SnapshotStore {
    /// Must match the `com.apple.security.application-groups` entitlement on both targets.
    ///
    /// Apple requires macOS app group identifiers to be prefixed with the Development Team ID (the
    /// bare `group.` form is the iOS convention). Building this repo under a different team means
    /// changing this string and both `.entitlements` files together — see README.
    public static let appGroupID = "5CYP2XRG73.de.justinscholz.SiriAIIndexStatus"

    public struct Snapshot: Codable, Sendable, Hashable {
        public let status: IndexStatus
        /// When the app last read the reports — not when the reports themselves were written.
        /// `status.reportDate` is the latter, and the two can be a day apart (ADR-0002).
        public let capturedAt: Date
        public let failure: String?

        public init(status: IndexStatus, capturedAt: Date = Date(), failure: String? = nil) {
            self.status = status
            self.capturedAt = capturedAt
            self.failure = failure
        }

        /// How long ago the app last managed to read anything. Large values mean the app is not
        /// running, not that indexing stalled.
        public func staleness(now: Date = Date()) -> TimeInterval {
            now.timeIntervalSince(capturedAt)
        }
    }

    public enum StoreError: LocalizedError {
        /// The App Group container is missing: entitlement absent, or the build is signed with an
        /// identity the group is not provisioned for.
        case containerUnavailable(String)
        case noSnapshotYet

        public var errorDescription: String? {
            switch self {
            case .containerUnavailable(let group):
                "App Group container \(group) is unavailable — check the entitlement and signature."
            case .noSnapshotYet:
                "The menu bar app has not written a snapshot yet."
            }
        }
    }

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    public static func fileURL() throws -> URL {
        guard let containerURL else { throw StoreError.containerUnavailable(appGroupID) }
        return containerURL.appending(path: "snapshot.json")
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

    /// Written atomically: the widget can wake mid-write, and a truncated read would blank a
    /// display that was otherwise correct.
    public static func write(_ snapshot: Snapshot, to url: URL? = nil) throws {
        try encoder.encode(snapshot).write(to: url ?? fileURL(), options: .atomic)
    }

    public static func read(from url: URL? = nil) throws -> Snapshot {
        let url = try url ?? fileURL()
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw StoreError.noSnapshotYet
        }
        return try decoder.decode(Snapshot.self, from: Data(contentsOf: url))
    }
}
