import Foundation

/// One app's standing in one pipeline, carrying the pipeline it belongs to.
///
/// `AppProgress` deliberately does not know its own pipeline — it is a row *inside* a
/// `PipelineProgress`. The developer-facing question runs the other way round ("what has the index
/// done with what *my* app donated?"), and that needs the pipeline attached to each row.
public struct AppPipelineStanding: Sendable, Hashable, Identifiable, Codable {
    public let pipeline: String
    public let completeness: Double
    public let eligibleItems: Int

    public var id: String { pipeline }

    public init(pipeline: String, completeness: Double, eligibleItems: Int) {
        self.pipeline = pipeline
        self.completeness = completeness
        self.eligibleItems = eligibleItems
    }

    public var displayName: String { DisplayNames.pipeline(for: pipeline) }

    /// Items of this app's the pipeline has still to get through.
    ///
    /// Rounded, not truncated: the reports carry a fraction, so 0.999 of 1,204 is "1 left", and
    /// truncation would call that zero and read as finished.
    public var remainingItems: Int {
        max(0, Int((Double(eligibleItems) * (1 - completeness)).rounded()))
    }

    public var indexedItems: Int { max(0, eligibleItems - remainingItems) }

    /// Matches `PipelineProgress.laggards`, which treats 0.999 as done.
    public var isComplete: Bool { completeness >= 0.999 }
}

/// Everything the reports say about one bundle identifier, across every pipeline.
public struct AppStanding: Sendable, Hashable, Identifiable, Codable {
    public let bundleID: String
    /// Pipelines carrying a row for this app, most work remaining first.
    public let standings: [AppPipelineStanding]
    /// Pipelines that exist on this Mac but carry no row for this app.
    ///
    /// Absence is an answer, not a gap: for a developer asking "is my app being picked up at all",
    /// a missing row is the whole finding, so it is carried explicitly rather than left implicit.
    public let absentFromPipelines: [String]

    public var id: String { bundleID }

    public init(bundleID: String, standings: [AppPipelineStanding], absentFromPipelines: [String]) {
        self.bundleID = bundleID
        self.standings = standings
        self.absentFromPipelines = absentFromPipelines
    }

    public var displayName: String { DisplayNames.app(for: bundleID) }

    /// The largest eligible-item count across pipelines — a ranking key, never a total. Counts from
    /// different pipelines measure different eligibility sets; adding them up would produce a
    /// number that describes nothing (ADR-0003 is the same mistake one level up).
    public var largestEligibleItems: Int { standings.map(\.eligibleItems).max() ?? 0 }

    public var isCompleteEverywhere: Bool {
        !standings.isEmpty && standings.allSatisfy(\.isComplete)
    }
}

extension IndexStatus {
    /// Every bundle identifier the reports mention.
    ///
    /// `all` rows never appear here: `IndexStatusBuilder` pulls them out as the pipeline aggregate
    /// before `apps` is built (ADR-0003).
    public var donatingBundleIDs: [String] {
        Set(pipelines.flatMap { $0.apps.map(\.bundleID) }).sorted()
    }

    /// What every pipeline says about one bundle identifier, or nil when no pipeline mentions it.
    public func standing(forBundleID bundleID: String) -> AppStanding? {
        var present: [AppPipelineStanding] = []
        var absent: [String] = []

        for pipeline in pipelines {
            if let app = pipeline.apps.first(where: { $0.bundleID == bundleID }) {
                present.append(
                    AppPipelineStanding(
                        pipeline: pipeline.pipeline,
                        completeness: app.completeness,
                        eligibleItems: app.eligibleItems
                    )
                )
            } else {
                absent.append(pipeline.pipeline)
            }
        }

        guard !present.isEmpty else { return nil }
        present.sort { $0.remainingItems > $1.remainingItems }
        return AppStanding(bundleID: bundleID, standings: present, absentFromPipelines: absent)
    }

    /// Apps whose bundle identifier or display name contains `query`, biggest first.
    ///
    /// Matching is on the raw identifier as well as the pretty name because a developer knows their
    /// bundle ID and may never have seen what `DisplayNames` makes of it.
    public func appStandings(matching query: String = "") -> [AppStanding] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return donatingBundleIDs
            .filter { bundleID in
                guard !needle.isEmpty else { return true }
                return bundleID.lowercased().contains(needle)
                    || DisplayNames.app(for: bundleID).lowercased().contains(needle)
            }
            .compactMap { standing(forBundleID: $0) }
            .sorted { lhs, rhs in
                if lhs.largestEligibleItems != rhs.largestEligibleItems {
                    return lhs.largestEligibleItems > rhs.largestEligibleItems
                }
                return lhs.bundleID < rhs.bundleID
            }
    }
}
