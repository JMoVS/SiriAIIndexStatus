import XCTest
@testable import SiriIndexCore

/// The reports carry no history — macOS overwrites them in place — so every figure here comes
/// from the app's own log of past readings. The numbers used are two real Embedding checkpoints
/// off this Mac: 2026-08-12 and 2026-08-25.
final class ProgressHistoryTests: XCTestCase {
    private static let august12 = Date(timeIntervalSinceReferenceDate: 808_142_663)
    private static let august25 = Date(timeIntervalSinceReferenceDate: 809_337_883.489249)

    private func status(
        _ pipelines: [(String, Double, Int, Date, [(String, Double, Int)])]
    ) -> IndexStatus {
        IndexStatus(
            pipelines: pipelines.map { pipeline, completeness, items, date, apps in
                PipelineProgress(
                    pipeline: pipeline,
                    completeness: completeness,
                    eligibleItems: items,
                    reportDate: date,
                    apps: apps.map { AppProgress(bundleID: $0.0, completeness: $0.1, eligibleItems: $0.2) },
                    headlineIsDerived: false
                )
            },
            reportDate: pipelines.map(\.3).max(),
            updaterRunning: true
        )
    }

    private func embedding(_ completeness: Double, _ items: Int, _ date: Date, apps: [(String, Double, Int)] = []) -> IndexStatus {
        status([("Embedding", completeness, items, date, apps)])
    }

    // MARK: - Recording

    /// The store polls every ten minutes and the reports move about once a day, so ~140 of every
    /// 144 readings are a re-read of a checkpoint already recorded. Appending those would push the
    /// only useful comparison — the previous *report* — out of a 60-entry log within half a day.
    func testRereadingTheSameCheckpointReplacesItRatherThanAppending() {
        let reading = embedding(0.5256729497833241, 207_222, Self.august25)
        var history: [IndexObservation] = []
        for minute in 0..<12 {
            history = HistoryStore.recording(
                reading, at: Self.august25.addingTimeInterval(Double(minute) * 600), into: history
            )
        }

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].recordedAt, Self.august25.addingTimeInterval(6_600))
    }

    func testNewReportDateAppends() {
        var history = HistoryStore.recording(embedding(0.487, 202_447, Self.august12), at: Self.august12, into: [])
        history = HistoryStore.recording(embedding(0.5256729497833241, 207_222, Self.august25), at: Self.august25, into: history)

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.last?.status.reportDate, Self.august25)
    }

    func testLogIsTrimmedFromTheOldestEnd() {
        var history: [IndexObservation] = []
        for day in 0...HistoryStore.maximumObservations {
            let date = Self.august12.addingTimeInterval(Double(day) * 86_400)
            history = HistoryStore.recording(embedding(0.4, 200_000, date), at: date, into: history)
        }

        XCTAssertEqual(history.count, HistoryStore.maximumObservations)
        XCTAssertEqual(history.first?.status.reportDate, Self.august12.addingTimeInterval(86_400))
    }

    /// A failed read leaves `.empty` on screen deliberately (the last good snapshot stays). Writing
    /// that into the log would invent a checkpoint at zero and report the next real reading as a
    /// day of miraculous progress.
    func testEmptyOrUndatedReadingsAreNotRecorded() {
        XCTAssertTrue(HistoryStore.recording(.empty, at: Self.august25, into: []).isEmpty)
        let undated = status([("Embedding", 0.5, 100, Self.august25, [])])
        let noDate = IndexStatus(pipelines: undated.pipelines, reportDate: nil, updaterRunning: true)
        XCTAssertTrue(HistoryStore.recording(noDate, at: Self.august25, into: []).isEmpty)
    }

    /// The bug this guards, caught on screen rather than here: report dates carry a fractional
    /// part (`809337883.489249`) and ISO 8601 does not. Every reading reloaded from the log came
    /// back a half-second off the one just read from the plist, so the "same checkpoint" test
    /// never matched — the log grew by one copy per ten-minute poll, and the panel compared the
    /// current reading against itself and said "No change in the 1m to this report".
    func testARereadIsStillTheSameCheckpointAfterARoundTripThroughDisk() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let reading = embedding(0.5256729497833241, 207_222, Self.august25)
        for minute in 0..<5 {
            try HistoryStore.record(reading, at: Self.august25.addingTimeInterval(Double(minute) * 600), in: url)
        }

        XCTAssertEqual(try HistoryStore.load(from: url).count, 1)
        XCTAssertNil(IndexDelta.latest(in: try HistoryStore.load(from: url)),
                     "a checkpoint is not its own predecessor")
    }

    /// Same fractional-second trap one level down: a genuine earlier checkpoint must still be
    /// found once its date has been through the log.
    func testProgressSurvivesTheRoundTripThroughDisk() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try HistoryStore.record(embedding(0.487, 202_447, Self.august12), at: Self.august12, in: url)
        try HistoryStore.record(embedding(0.5256729497833241, 207_222, Self.august25), at: Self.august25, in: url)

        let delta = try XCTUnwrap(IndexDelta.latest(in: try HistoryStore.load(from: url))?["Embedding"])
        XCTAssertEqual(delta.indexedItemsChange, 10_339)
        XCTAssertGreaterThan(delta.span, 12 * 86_400)
    }

    func testRoundTripsThroughDisk() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(try HistoryStore.load(from: url).isEmpty, "a missing file is not an error")
        try HistoryStore.record(embedding(0.487, 202_447, Self.august12), at: Self.august12, in: url)
        let history = try HistoryStore.record(embedding(0.5256729497833241, 207_222, Self.august25), at: Self.august25, in: url)

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(try HistoryStore.load(from: url).count, 2)
    }

    // MARK: - Deltas

    func testNoComparisonUntilASecondCheckpointExists() {
        let history = HistoryStore.recording(embedding(0.487, 202_447, Self.august12), at: Self.august12, into: [])
        XCTAssertNil(IndexDelta.latest(in: history))
    }

    /// Real figures: Embedding went 0.487 of 202,447 → 0.5257 of 207,222 between the two reports.
    func testProgressBetweenTwoRealCheckpoints() throws {
        var history = HistoryStore.recording(embedding(0.487, 202_447, Self.august12), at: Self.august12, into: [])
        history = HistoryStore.recording(embedding(0.5256729497833241, 207_222, Self.august25), at: Self.august25, into: history)

        let delta = try XCTUnwrap(IndexDelta.latest(in: history)?["Embedding"])
        XCTAssertEqual(delta.indexedItemsChange, 10_339)
        XCTAssertEqual(delta.eligibleItemsChange, 4_775)
        XCTAssertEqual(delta.completenessChange, 0.0386729497833241, accuracy: 0.000_001)
        XCTAssertEqual(delta.previousCompleteness, 0.487, accuracy: 0.000_001)
        XCTAssertEqual(delta.currentCompleteness, 0.5256729497833241, accuracy: 0.000_001)
        XCTAssertEqual(delta.span, Self.august25.timeIntervalSince(Self.august12), accuracy: 1)
        XCTAssertTrue(delta.hasMovement)
    }

    /// The reason the item count leads the display and the percentage follows it. Here the indexer
    /// got through 10,000 items while 30,000 more became eligible: real work, negative percentage.
    func testPercentageFallsWhileWorkIsDone() throws {
        var history = HistoryStore.recording(embedding(0.5, 200_000, Self.august12), at: Self.august12, into: [])
        history = HistoryStore.recording(embedding(0.478_260_869_565_217_4, 230_000, Self.august25), at: Self.august25, into: history)

        let delta = try XCTUnwrap(IndexDelta.latest(in: history)?["Embedding"])
        XCTAssertEqual(delta.indexedItemsChange, 10_000)
        XCTAssertLessThan(delta.completenessChange, 0)
        XCTAssertTrue(delta.hasMovement, "a day of indexing is movement even when the percentage dropped")
    }

    /// Pipelines are written by separate jobs and do not all move together. Comparing every
    /// pipeline against one global baseline would report "no change" for whichever ones missed the
    /// latest write — a fact about the report schedule, not about indexing.
    func testEachPipelineIsComparedAgainstItsOwnPreviousReport() throws {
        let august20 = Self.august12.addingTimeInterval(8 * 86_400)
        var history = HistoryStore.recording(
            status([
                ("Embedding", 0.487, 202_447, Self.august12, []),
                ("Keyphrase", 0.9, 50_000, Self.august12, []),
            ]),
            at: Self.august12, into: []
        )
        // Keyphrase moved on the 20th, Embedding did not.
        history = HistoryStore.recording(
            status([
                ("Embedding", 0.487, 202_447, Self.august12, []),
                ("Keyphrase", 0.95, 50_000, august20, []),
            ]),
            at: august20, into: history
        )
        // Embedding moved on the 25th, Keyphrase did not.
        history = HistoryStore.recording(
            status([
                ("Embedding", 0.5256729497833241, 207_222, Self.august25, []),
                ("Keyphrase", 0.95, 50_000, august20, []),
            ]),
            at: Self.august25, into: history
        )

        let delta = try XCTUnwrap(IndexDelta.latest(in: history))
        let embedding = try XCTUnwrap(delta["Embedding"])
        XCTAssertEqual(embedding.previousDate, Self.august12, "the 20th carried the same Embedding report")
        XCTAssertEqual(embedding.indexedItemsChange, 10_339)

        let keyphrase = try XCTUnwrap(delta["Keyphrase"])
        XCTAssertEqual(keyphrase.currentDate, august20)
        XCTAssertEqual(keyphrase.previousDate, Self.august12)
        XCTAssertEqual(keyphrase.completenessChange, 0.05, accuracy: 0.000_001)
    }

    /// Real figures again: com.apple.mail went 0.261 of 118,195 → 0.2723 of 118,550.
    func testPerAppProgressAndFirstAppearance() throws {
        var history = HistoryStore.recording(
            embedding(0.487, 202_447, Self.august12, apps: [("com.apple.mail", 0.261, 118_195)]),
            at: Self.august12, into: []
        )
        history = HistoryStore.recording(
            embedding(
                0.5256729497833241, 207_222, Self.august25,
                apps: [("com.apple.mail", 0.2723407844791227, 118_550), ("com.apple.reminders", 0.6900375350600969, 304)]
            ),
            at: Self.august25, into: history
        )

        let delta = try XCTUnwrap(IndexDelta.latest(in: history)?["Embedding"])
        let mail = try XCTUnwrap(delta.app("com.apple.mail"))
        XCTAssertEqual(mail.indexedItemsChange, 1_437)
        XCTAssertEqual(mail.eligibleItemsChange, 355)
        XCTAssertFalse(mail.isNew)

        // An app that was absent last time has no progress to report — its whole count arrived at
        // once, and calling that a day's indexing would overstate every new donor.
        let reminders = try XCTUnwrap(delta.app("com.apple.reminders"))
        XCTAssertTrue(reminders.isNew)
        XCTAssertEqual(reminders.completenessChange, 0)
        XCTAssertEqual(delta.movers.first?.bundleID, "com.apple.mail")
    }
}
