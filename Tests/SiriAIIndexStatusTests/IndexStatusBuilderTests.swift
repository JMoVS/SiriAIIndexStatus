import XCTest
@testable import SiriIndexCore

final class IndexStatusBuilderTests: XCTestCase {
    private func row(
        _ pipeline: String, _ bundleID: String, _ completeness: Double, _ items: Int
    ) -> PipelineCompletenessReport {
        PipelineCompletenessReport(
            pipeline: pipeline, bundleID: bundleID,
            completeness: completeness, heuristicScore: completeness,
            eligibleItems: items, reportDate: Date(timeIntervalSinceReferenceDate: 808_142_663)
        )
    }

    /// The bug this guards: treating `all` as a sibling of the per-app rows double-counts every
    /// item (ADR-0003). Real numbers — 202,447 eligible, not 404,894.
    func testAggregateRowIsTheHeadlineAndIsNotCountedTwice() {
        let status = IndexStatusBuilder.build(
            from: [
                row("Embedding", "all", 0.487, 202_447),
                row("Embedding", "com.apple.mail", 0.261, 118_195),
                row("Embedding", "com.apple.CalendarUI", 0.999, 24_813),
            ],
            updaterRunning: true
        )

        let embedding = try? XCTUnwrap(status.headline)
        XCTAssertEqual(embedding?.eligibleItems, 202_447)
        XCTAssertEqual(embedding?.completeness ?? 0, 0.487, accuracy: 0.0001)
        XCTAssertEqual(embedding?.apps.count, 2, "the `all` row must not appear as an app")
        XCTAssertFalse(embedding?.headlineIsDerived ?? true)
    }

    func testHeadlineFallsBackToItemWeightedMeanWhenAggregateRowIsAbsent() {
        let status = IndexStatusBuilder.build(
            from: [
                row("Keyphrase", "com.apple.mail", 0.0, 100),
                row("Keyphrase", "com.apple.Notes", 1.0, 300),
            ],
            updaterRunning: false
        )

        let keyphrase = status.pipelines.first
        XCTAssertEqual(keyphrase?.completeness ?? 0, 0.75, accuracy: 0.0001)
        XCTAssertEqual(keyphrase?.eligibleItems, 400)
        XCTAssertTrue(keyphrase?.headlineIsDerived ?? false)
    }

    func testLaggardsRankByRemainingItemsNotByPercentage() {
        let status = IndexStatusBuilder.build(
            from: [
                row("Embedding", "all", 0.5, 1000),
                // 2% of 8,642 done → ~8,469 remaining.
                row("Embedding", "com.apple.helpviewer", 0.022, 8_642),
                // 26% of 118,195 done → ~87,000 remaining: the real bottleneck despite a higher %.
                row("Embedding", "com.apple.mail", 0.261, 118_195),
            ],
            updaterRunning: true
        )

        XCTAssertEqual(status.headline?.laggards.first?.bundleID, "com.apple.mail")
    }

    func testCompletePipelinesReportComplete() {
        let status = IndexStatusBuilder.build(
            from: [row("Embedding", "all", 1.0, 10)],
            updaterRunning: false
        )
        XCTAssertTrue(status.isComplete)
    }

    func testEmptyInputIsNotReportedComplete() {
        let status = IndexStatusBuilder.build(from: [], updaterRunning: false)
        XCTAssertFalse(status.isComplete)
        XCTAssertNil(status.reportDate)
    }

    func testDisplayNamesFallBackForUnknownIdentifiers() {
        XCTAssertEqual(DisplayNames.pipeline(for: "Embedding"), "Embedding (semantic vectors)")
        XCTAssertEqual(DisplayNames.pipeline(for: "LSSR5EventsandordersUrgent"), "Events & orders (urgent)")
        XCTAssertEqual(DisplayNames.app(for: "com.apple.mail"), "Mail")
        XCTAssertEqual(DisplayNames.app(for: "com.example.SomeNewApp"), "Some New App")
    }

    func testPercentFormatting() {
        XCTAssertEqual(Formatting.percent(0.4872972), "48.7%")
        XCTAssertEqual(Formatting.compactPercent(0.4872972), "49%")
        XCTAssertEqual(Formatting.itemCount(202_447).filter(\.isNumber), "202447")
    }
}
