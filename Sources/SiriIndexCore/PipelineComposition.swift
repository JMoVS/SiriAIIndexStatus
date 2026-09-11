import Foundation

/// Why a donor's numbers changed between the last two reports.
///
/// The distinction WL-12 is about: a row can move because the indexer got through items, or
/// because the eligible set it is measured against changed size. Both show up as a moving
/// percentage and only one of them is indexing.
public enum DonorMovement: Sendable, Hashable, Codable {
    /// Items were indexed and the eligible set moved less than the work did.
    case indexed(items: Int)
    /// The eligible set moved further than the indexed count — the percentage moved, the index
    /// mostly did not. Carries both so the UI never has to imply the scope change was work.
    case scopeChanged(eligibleItems: Int, indexedItems: Int)
    /// The donor carried no row in the earlier report, so its whole count is arrival, not progress.
    case arrived(items: Int)
    /// Neither figure moved.
    case still
    /// No earlier report to compare against.
    case unknown

    public var isIndexing: Bool {
        if case .indexed = self { return true }
        return false
    }
}

/// One donor's part in a pipeline's headline percentage.
public struct DonorShare: Sendable, Hashable, Codable, Identifiable {
    public let bundleID: String
    public let completeness: Double
    public let eligibleItems: Int
    /// This donor's fraction of the pipeline's eligible total.
    public let share: Double
    /// Points of the headline this donor is withholding: `share × (1 - completeness)`.
    ///
    /// The reason this is the sort key rather than remaining items: these sum exactly to
    /// `1 - pipeline.completeness`, so the list is a decomposition of the missing percentage
    /// rather than a ranking beside it. "Why is it 47%" has a complete answer in three rows.
    public let withheld: Double
    public let movement: DonorMovement

    public var id: String { bundleID }

    public var displayName: String { DisplayNames.app(for: bundleID) }

    public init(
        bundleID: String,
        completeness: Double,
        eligibleItems: Int,
        share: Double,
        withheld: Double,
        movement: DonorMovement
    ) {
        self.bundleID = bundleID
        self.completeness = completeness
        self.eligibleItems = eligibleItems
        self.share = share
        self.withheld = withheld
        self.movement = movement
    }
}

/// What a pipeline's headline percentage is actually made of.
///
/// Measured 2026-09-11, `Embedding` sat at 47.3% for weeks while Mail quietly embedded ~6,400
/// messages, because 17.6% of the denominator belongs to a donor whose eligible set swings by tens
/// of thousands and 6.4% belongs to one frozen at 2.2%. The percentage alone cannot tell those
/// apart; this can. See `docs/notes/20260911-what-the-headline-percentage-measures.md`.
public struct PipelineComposition: Sendable, Hashable, Codable {
    /// Every donor, most headline points withheld first.
    public let donors: [DonorShare]
    /// Items indexed since the last report by donors whose eligible set held steady.
    public let indexedItems: Int
    /// Net change in the eligible total across donors whose denominator moved further than their
    /// indexed count did.
    public let scopeItems: Int

    public init(donors: [DonorShare], indexedItems: Int, scopeItems: Int) {
        self.donors = donors
        self.indexedItems = indexedItems
        self.scopeItems = scopeItems
    }

    /// The few donors that explain most of the missing percentage, plus everything else folded up.
    ///
    /// `limit` rows at most, and never a row for a donor withholding less than a tenth of a point —
    /// a list that ends in four rows reading `0.0` looks like precision and carries nothing.
    public func principals(limit: Int = 3) -> (rows: [DonorShare], otherCount: Int, otherWithheld: Double) {
        let material = donors.filter { $0.withheld >= 0.001 }
        let rows = Array(material.prefix(limit))
        let rest = donors.dropFirst(rows.count)
        return (rows, rest.count, rest.reduce(0) { $0 + $1.withheld })
    }

    /// True when the last report's movement came more from the size of the total than from work.
    ///
    /// The case this exists for: 2026-09-08, where `Embedding` fell 51.3% → 47.3% purely because
    /// one donor's eligible set grew by 12,400 items. Reporting that as a 4-point regression is
    /// reporting a bookkeeping change as an indexing failure.
    public var isDominatedByScopeChange: Bool {
        abs(scopeItems) > abs(indexedItems)
    }

    /// Share of the eligible total held by donors that are incomplete and did not move at all.
    public var stalledShare: Double {
        donors.filter { $0.movement == .still && $0.completeness < 0.999 }
            .reduce(0) { $0 + $1.share }
    }
}

extension PipelineProgress {
    /// Break the headline down into the donors that produce it.
    ///
    /// `delta` is optional because the first reading after launch has no baseline — the shares and
    /// withheld points are computed from the snapshot alone, and only the movement column needs
    /// history.
    public func composition(delta: PipelineDelta? = nil) -> PipelineComposition {
        let total = apps.reduce(0) { $0 + $1.eligibleItems }
        guard total > 0 else { return PipelineComposition(donors: [], indexedItems: 0, scopeItems: 0) }

        let donors = apps.map { app -> DonorShare in
            let share = Double(app.eligibleItems) / Double(total)
            return DonorShare(
                bundleID: app.bundleID,
                completeness: app.completeness,
                eligibleItems: app.eligibleItems,
                share: share,
                withheld: share * (1 - min(max(app.completeness, 0), 1)),
                movement: Self.movement(of: delta?.app(app.bundleID))
            )
        }
        .sorted { lhs, rhs in
            if lhs.withheld != rhs.withheld { return lhs.withheld > rhs.withheld }
            return lhs.eligibleItems > rhs.eligibleItems
        }

        var indexed = 0
        var scope = 0
        for donor in donors {
            switch donor.movement {
            case .indexed(let items): indexed += items
            case .scopeChanged(let eligibleItems, let indexedItems):
                scope += eligibleItems
                indexed += indexedItems
            case .arrived, .still, .unknown: break
            }
        }

        return PipelineComposition(donors: donors, indexedItems: indexed, scopeItems: scope)
    }

    /// A nil `AppDelta` means no baseline: `IndexDelta` builds one row per app in the current
    /// report, so a donor present now is never missing from a delta that exists.
    private static func movement(of delta: AppDelta?) -> DonorMovement {
        guard let delta else { return .unknown }
        if delta.isNew { return .arrived(items: delta.eligibleItemsChange) }
        guard delta.hasMovement else { return .still }
        // Strictly greater: a donor that indexed exactly as many items as arrived did the work,
        // and calling that a scope change would hide a day of indexing behind a tie.
        if abs(delta.eligibleItemsChange) > abs(delta.indexedItemsChange) {
            return .scopeChanged(
                eligibleItems: delta.eligibleItemsChange,
                indexedItems: delta.indexedItemsChange
            )
        }
        return .indexed(items: delta.indexedItemsChange)
    }
}
