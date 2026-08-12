import Foundation
import XCTest

@testable import SiriIndexCore

/// The snapshot file is the only thing the widget ever reads (ADR-0005). App and widget are
/// separate processes built as separate targets, so nothing but this encoding keeps them agreeing —
/// which makes the round trip worth pinning.
final class SnapshotStoreTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "snapshot-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private var sampleStatus: IndexStatus {
        IndexStatus(
            pipelines: [
                PipelineProgress(
                    pipeline: "Embedding",
                    completeness: 0.2637,
                    eligibleItems: 404_894,
                    reportDate: Date(timeIntervalSince1970: 1_786_000_000),
                    apps: [
                        AppProgress(bundleID: "cs_mail", completeness: 0.26, eligibleItems: 400_000),
                        AppProgress(bundleID: "cs_notes", completeness: 1.0, eligibleItems: 4_894),
                    ],
                    headlineIsDerived: false
                )
            ],
            reportDate: Date(timeIntervalSince1970: 1_786_000_000),
            updaterRunning: true
        )
    }

    func testRoundTripPreservesEveryFigureTheWidgetDraws() throws {
        let written = SnapshotStore.Snapshot(
            status: sampleStatus,
            capturedAt: Date(timeIntervalSince1970: 1_786_003_600),
            failure: nil
        )
        try SnapshotStore.write(written, to: url)
        let read = try SnapshotStore.read(from: url)

        XCTAssertEqual(read, written)
        // Spelled out, because `==` on the struct would still pass if the widget's headline lookup
        // were reading a field that round-tripped as nil.
        let headline = try XCTUnwrap(read.status.headline)
        XCTAssertEqual(headline.pipeline, "Embedding")
        XCTAssertEqual(headline.completeness, 0.2637, accuracy: 0.00001)
        XCTAssertEqual(headline.eligibleItems, 404_894)
        XCTAssertEqual(headline.apps.count, 2)
        XCTAssertEqual(read.status.updaterRunning, true)
        XCTAssertNotNil(read.status.reportDate)
    }

    /// A failed read still publishes: the widget has no other way to learn the app is stuck, and
    /// blanking a display that was correct a minute ago is worse than saying why it stopped.
    func testFailureSurvivesTheRoundTripAlongsideTheLastGoodStatus() throws {
        let written = SnapshotStore.Snapshot(
            status: sampleStatus,
            capturedAt: Date(timeIntervalSince1970: 1_786_003_600),
            failure: "Full Disk Access is required to read PipelineCompletenessReporting."
        )
        try SnapshotStore.write(written, to: url)
        let read = try SnapshotStore.read(from: url)

        XCTAssertEqual(read.failure, written.failure)
        XCTAssertNotNil(read.status.headline, "a failure must not discard the last good numbers")
    }

    func testMissingFileIsItsOwnErrorRatherThanADecodeFailure() {
        XCTAssertThrowsError(try SnapshotStore.read(from: url)) { error in
            guard case SnapshotStore.StoreError.noSnapshotYet = error else {
                return XCTFail("expected .noSnapshotYet, got \(error)")
            }
        }
    }

    /// The app writes every poll while the widget may read at any moment, so the write has to be
    /// atomic — a half-written file would decode as garbage rather than as "not ready yet".
    func testOverwritingAnExistingSnapshotLeavesAValidFile() throws {
        try SnapshotStore.write(
            SnapshotStore.Snapshot(status: .empty, capturedAt: Date(timeIntervalSince1970: 1), failure: nil),
            to: url
        )
        let second = SnapshotStore.Snapshot(
            status: sampleStatus,
            capturedAt: Date(timeIntervalSince1970: 1_786_003_600),
            failure: nil
        )
        try SnapshotStore.write(second, to: url)

        XCTAssertEqual(try SnapshotStore.read(from: url), second)
    }
}
