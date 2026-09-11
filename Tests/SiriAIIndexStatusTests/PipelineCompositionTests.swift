import XCTest
@testable import SiriIndexCore

/// Built from the real `Embedding` report of 2026-09-10, because the whole point of the type is
/// that these particular numbers mislead in the aggregate: 47.3% for weeks while Mail quietly
/// embedded ~6,400 messages. See
/// `docs/notes/20260911-what-the-headline-percentage-measures.md`.
final class PipelineCompositionTests: XCTestCase {
    /// All 22 donor rows, not the interesting five — the withheld points are a decomposition of
    /// the missing percentage, and a decomposition of a truncated denominator is a different
    /// number that happens to look plausible.
    private static let embedding = PipelineProgress(
        pipeline: "Embedding",
        completeness: 0.472_750,
        eligibleItems: 205_341,
        reportDate: Date(timeIntervalSinceReferenceDate: 810_719_932),
        apps: [
            AppProgress(bundleID: "com.apple.mail", completeness: 0.326459, eligibleItems: 118_508),
            AppProgress(bundleID: "com.nextcloud.desktopclient", completeness: 0.603625, eligibleItems: 36_140),
            AppProgress(bundleID: "com.apple.CalendarUI", completeness: 0.989805, eligibleItems: 24_915),
            AppProgress(bundleID: "com.apple.helpviewer", completeness: 0.021884, eligibleItems: 13_069),
            AppProgress(bundleID: "com.apple.MobileSMS", completeness: 0.995694, eligibleItems: 9_057),
            AppProgress(bundleID: "com.apple.systempreferences", completeness: 0.002653, eligibleItems: 754),
            AppProgress(bundleID: "com.apple.shortcuts", completeness: 0.926087, eligibleItems: 460),
            AppProgress(bundleID: "com.omnigroup.OmniFocus4", completeness: 0.975556, eligibleItems: 450),
            AppProgress(bundleID: "io.mountainduck", completeness: 0.948956, eligibleItems: 431),
            AppProgress(bundleID: "com.apple.Notes", completeness: 0.938375, eligibleItems: 357),
            AppProgress(bundleID: "com.apple.reminders", completeness: 1.000000, eligibleItems: 305),
            AppProgress(bundleID: "com.apple.spotlight.events", completeness: 0.983871, eligibleItems: 248),
            AppProgress(bundleID: "com.apple.Safari", completeness: 0.715976, eligibleItems: 169),
            AppProgress(bundleID: "com.apple.appplaceholdersyncd", completeness: 0.283784, eligibleItems: 148),
            AppProgress(bundleID: "com.apple.podcasts", completeness: 1.000000, eligibleItems: 142),
            AppProgress(bundleID: "com.apple.mobilephone", completeness: 1.000000, eligibleItems: 104),
            AppProgress(bundleID: "com.surteesstudios.Bartender", completeness: 0.000000, eligibleItems: 36),
            AppProgress(bundleID: "com.apple.freeform", completeness: 0.666667, eligibleItems: 21),
            AppProgress(bundleID: "com.microsoft.Excel", completeness: 0.812500, eligibleItems: 16),
            AppProgress(bundleID: "com.microsoft.Powerpoint", completeness: 1.000000, eligibleItems: 8),
            AppProgress(bundleID: "com.microsoft.Word", completeness: 1.000000, eligibleItems: 2),
            AppProgress(bundleID: "com.apple.AppStore", completeness: 1.000000, eligibleItems: 1),
        ],
        headlineIsDerived: false
    )

    /// `IndexDelta` emits one row per app in the current report, so a realistic delta carries all
    /// 22. Everything not named here held still.
    private static func delta(_ overrides: [String: (indexed: Int, eligible: Int)]) -> PipelineDelta {
        PipelineDelta(
            pipeline: "Embedding",
            previousDate: Date(timeIntervalSinceReferenceDate: 810_633_532),
            currentDate: Date(timeIntervalSinceReferenceDate: 810_719_932),
            previousCompleteness: 0.513,
            currentCompleteness: 0.473,
            indexedItemsChange: overrides.values.reduce(0) { $0 + $1.indexed },
            eligibleItemsChange: overrides.values.reduce(0) { $0 + $1.eligible },
            apps: embedding.apps.map { app in
                let moved = overrides[app.bundleID] ?? (indexed: 0, eligible: 0)
                return AppDelta(
                    bundleID: app.bundleID,
                    completenessChange: 0,
                    indexedItemsChange: moved.indexed,
                    eligibleItemsChange: moved.eligible,
                    isNew: false
                )
            }
        )
    }

    private func donor(_ bundleID: String, in composition: PipelineComposition) -> DonorShare {
        composition.donors.first { $0.bundleID == bundleID }!
    }

    /// The identity the display leans on: the per-donor withheld points are a decomposition of the
    /// missing percentage, not a ranking alongside it. If this drifts, the panel is doing
    /// arithmetic that does not add up while claiming it does.
    func testWithheldPointsSumToTheMissingPercentage() {
        let composition = Self.embedding.composition()
        let total = composition.donors.reduce(0) { $0 + $1.withheld }
        XCTAssertEqual(total, 1 - 0.472_750_205_755_304_6, accuracy: 0.000_01,
                       "must reconstruct the aggregate row Apple wrote, not just some total")
    }

    /// Mail is 57.7% of the denominator at 32.6% complete, so it alone withholds 38.9 of the
    /// missing 52.7 points — the answer to "why has this said 47% for weeks".
    func testRanksDonorsByHeadlinePointsWithheldNotByRemainingItems() {
        let composition = Self.embedding.composition()

        XCTAssertEqual(Array(composition.donors.map(\.bundleID)[0..<3]), [
            "com.apple.mail", "com.nextcloud.desktopclient", "com.apple.helpviewer",
        ])
        XCTAssertEqual(composition.donors[0].share, 0.577_128, accuracy: 0.000_001)
        XCTAssertEqual(composition.donors[0].withheld, 0.388_719, accuracy: 0.000_001)
        XCTAssertEqual(composition.donors[1].withheld, 0.069_762, accuracy: 0.000_001)
        // Calendar has 254 items left against Help Viewer's 12,783, but the ordering that matters
        // is effect on the headline: Help Viewer costs 6.2 points, Calendar 0.1.
        XCTAssertEqual(composition.donors[2].withheld, 0.062_253, accuracy: 0.000_001)
        XCTAssertLessThan(donor("com.apple.CalendarUI", in: composition).withheld, 0.002)
    }

    /// 2026-09-08: the headline fell 51.3% → 47.3% while Mail indexed items and Nextcloud's
    /// eligible set grew 12,404. Calling that day a regression is the bug this flag prevents.
    func testScopeChangeIsSeparatedFromIndexingWork() {
        let composition = Self.embedding.composition(delta: Self.delta([
            "com.apple.mail": (indexed: 1_204, eligible: 30),
            "com.nextcloud.desktopclient": (indexed: 2_696, eligible: 12_404),
            "com.apple.CalendarUI": (indexed: 5, eligible: 5),
        ]))

        XCTAssertEqual(donor("com.apple.mail", in: composition).movement, .indexed(items: 1_204))
        XCTAssertEqual(donor("com.nextcloud.desktopclient", in: composition).movement,
                       .scopeChanged(eligibleItems: 12_404, indexedItems: 2_696))
        XCTAssertEqual(donor("com.apple.helpviewer", in: composition).movement, .still)
        // A tie goes to work: Calendar indexed the 5 items that arrived.
        XCTAssertEqual(donor("com.apple.CalendarUI", in: composition).movement, .indexed(items: 5))

        XCTAssertTrue(composition.isDominatedByScopeChange,
                      "12,404 items of denominator against 3,905 of work is not a day of indexing")
        XCTAssertEqual(composition.scopeItems, 12_404)
        // Work is still counted, including the part inside the row whose denominator churned.
        XCTAssertEqual(composition.indexedItems, 1_204 + 2_696 + 5)
    }

    /// Help Viewer: 13,069 items frozen at 2.2% for the whole 17-day window — 6.4% of the
    /// denominator that will not move, setting a ceiling the headline can never pass.
    func testStalledShareCountsOnlyIncompleteDonorsThatDidNotMove() {
        // Everything moves except Help Viewer and Reminders. Reminders is the control: motionless
        // but genuinely at 1.0, so it is finished rather than stalled and the correct stalled share
        // is Help Viewer's alone. Messages cannot play that role — 99.57% is below the 0.999
        // completion threshold, so a motionless Messages row *is* a stall, with 39 items left.
        var overrides: [String: (indexed: Int, eligible: Int)] = [:]
        for app in Self.embedding.apps
        where app.bundleID != "com.apple.helpviewer" && app.bundleID != "com.apple.reminders" {
            overrides[app.bundleID] = (indexed: 1, eligible: 0)
        }

        let composition = Self.embedding.composition(delta: Self.delta(overrides))
        XCTAssertEqual(composition.stalledShare, 13_069.0 / 205_341.0, accuracy: 0.000_001)
    }

    func testFirstReadingReportsUnknownMovementRatherThanNoChange() {
        let composition = Self.embedding.composition()
        XCTAssertTrue(composition.donors.allSatisfy { $0.movement == .unknown },
                      "no baseline is not the same statement as nothing happened")
        XCTAssertFalse(composition.isDominatedByScopeChange)
    }

    /// A tail of rows reading `0.0` is noise pretending to be precision.
    func testPrincipalsFoldTheImmaterialTailIntoACount() {
        let composition = Self.embedding.composition()
        let (rows, otherCount, otherWithheld) = composition.principals(limit: 3)

        XCTAssertEqual(rows.map(\.bundleID), [
            "com.apple.mail", "com.nextcloud.desktopclient", "com.apple.helpviewer",
        ])
        XCTAssertEqual(otherCount, 19)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.withheld } + otherWithheld,
                       composition.donors.reduce(0) { $0 + $1.withheld },
                       accuracy: 0.000_001,
                       "folding the tail must not lose points out of the decomposition")
    }
}
