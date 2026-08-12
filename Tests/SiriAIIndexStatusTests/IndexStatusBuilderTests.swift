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

    /// The widget draws the headline as a big number and `supporting` as the list beside it. When
    /// the headline pipeline is not the last one by completeness, taking the first four of
    /// `pipelines` prints it in both places and silently drops another — which is what a
    /// `prefix(4)` did until the real numbers happened to hide it (Embedding sorted last).
    func testSupportingExcludesTheHeadlineWhereverItSortsByCompleteness() {
        let status = IndexStatusBuilder.build(
            from: [
                row("Embedding", "all", 0.10, 200_000),
                row("Keyphrase", "all", 0.20, 100_000),
                row("LSSR5EventsandordersUrgent", "all", 0.30, 90_000),
                row("LSSR5EventsandordersBackground", "all", 0.40, 148_000),
                row("LSSR5IdentificationdocumentsBackground", "all", 0.50, 7_000),
            ],
            updaterRunning: false
        )

        XCTAssertEqual(status.headline?.pipeline, "Embedding", "Embedding is the headline (ADR-0003)")
        XCTAssertEqual(status.supporting.count, 4)
        XCTAssertFalse(
            status.supporting.contains { $0.pipeline == "Embedding" },
            "the headline pipeline must not also appear in the list beside it"
        )
        XCTAssertEqual(
            Set(status.supporting.map(\.pipeline)) .union(["Embedding"]),
            Set(status.pipelines.map(\.pipeline)),
            "and no other pipeline may be dropped to make room"
        )
    }

    func testEveryObservedPipelineHasAShortNameForTheWidget() {
        for pipeline in [
            "Embedding", "Keyphrase", "LSSR5EventsandordersUrgent",
            "LSSR5EventsandordersBackground", "LSSR5IdentificationdocumentsBackground",
        ] {
            let short = DisplayNames.shortPipeline(for: pipeline)
            XCTAssertFalse(short.isEmpty)
            XCTAssertLessThanOrEqual(short.count, 18, "\(short) will not fit a widget row")
            XCTAssertFalse(short.contains("LSSR5"), "\(pipeline) fell through to the raw identifier")
        }
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
