import Foundation

/// One donating app's progress within a pipeline.
public struct AppProgress: Sendable, Hashable, Identifiable, Codable {
    public let bundleID: String
    public let completeness: Double
    public let eligibleItems: Int

    public var id: String { bundleID }

    public init(bundleID: String, completeness: Double, eligibleItems: Int) {
        self.bundleID = bundleID
        self.completeness = completeness
        self.eligibleItems = eligibleItems
    }

    /// Last path component of the bundle id, title-cased enough to read in a menu.
    public var displayName: String { DisplayNames.app(for: bundleID) }
}

/// One indexing pipeline: its headline figure plus the per-app breakdown behind it.
public struct PipelineProgress: Sendable, Hashable, Identifiable, Codable {
    public let pipeline: String
    public let completeness: Double
    public let eligibleItems: Int
    public let reportDate: Date?
    public let apps: [AppProgress]
    /// True when no `all` row was present and the headline is an item-weighted mean of `apps`.
    public let headlineIsDerived: Bool

    public var id: String { pipeline }

    public var displayName: String { DisplayNames.pipeline(for: pipeline) }

    /// For the widget, where the full name does not fit beside a percentage.
    public var shortDisplayName: String { DisplayNames.shortPipeline(for: pipeline) }

    public init(
        pipeline: String,
        completeness: Double,
        eligibleItems: Int,
        reportDate: Date?,
        apps: [AppProgress],
        headlineIsDerived: Bool
    ) {
        self.pipeline = pipeline
        self.completeness = completeness
        self.eligibleItems = eligibleItems
        self.reportDate = reportDate
        self.apps = apps
        self.headlineIsDerived = headlineIsDerived
    }

    /// Apps furthest from done, biggest backlog first — what is actually holding the pipeline up.
    public var laggards: [AppProgress] {
        appsByRemainingItems.filter { $0.completeness < 0.999 }
    }

    /// Every donating app, biggest backlog first, finished ones included.
    ///
    /// `laggards` answers "what is holding this up" and so drops anything at 100%. A developer
    /// asking what the index has of *their* app needs the other answer: a row at 100% is the
    /// success case, and a view that can only show incomplete rows cannot report it.
    public var appsByRemainingItems: [AppProgress] {
        apps.sorted { lhs, rhs in
            let lhsRemaining = Double(lhs.eligibleItems) * (1 - lhs.completeness)
            let rhsRemaining = Double(rhs.eligibleItems) * (1 - rhs.completeness)
            if lhsRemaining != rhsRemaining { return lhsRemaining > rhsRemaining }
            return lhs.eligibleItems > rhs.eligibleItems
        }
    }
}

/// A full snapshot of the semantic index, as of one read of the report directory.
public struct IndexStatus: Sendable, Hashable, Codable {
    public let pipelines: [PipelineProgress]
    /// Newest `reportDate` across all pipelines — how stale the whole picture is.
    public let reportDate: Date?
    /// Whether `spotlightknowledged.updater` was running at snapshot time.
    public let updaterRunning: Bool

    public init(pipelines: [PipelineProgress], reportDate: Date?, updaterRunning: Bool) {
        self.pipelines = pipelines
        self.reportDate = reportDate
        self.updaterRunning = updaterRunning
    }

    public static let empty = IndexStatus(pipelines: [], reportDate: nil, updaterRunning: false)

    /// The pipeline the menu bar summarises. Embedding is the vector index — the one that gates
    /// semantic search working at all, so it is the headline (ADR-0003).
    public static let headlinePipeline = "Embedding"

    public var headline: PipelineProgress? {
        pipelines.first { $0.pipeline == Self.headlinePipeline } ?? pipelines.first
    }

    /// Every pipeline the headline is not already showing.
    ///
    /// Listing all of them next to the headline figure would print one pipeline twice, and which
    /// one gets duplicated depends on the sort order — `pipelines` is sorted by completeness, so
    /// the duplicate moves as the numbers move. The exclusion has to be by identity.
    public var supporting: [PipelineProgress] {
        guard let headline else { return [] }
        return pipelines.filter { $0.id != headline.id }
    }

    public var isComplete: Bool {
        !pipelines.isEmpty && pipelines.allSatisfy { $0.completeness >= 0.999 }
    }

    /// Age of the newest report, or nil when nothing has been read yet.
    public func age(now: Date = Date()) -> TimeInterval? {
        reportDate.map { now.timeIntervalSince($0) }
    }
}

public enum IndexStatusBuilder {
    /// Fold raw report rows into per-pipeline progress.
    ///
    /// The `all` row is the pipeline's own aggregate, so it is pulled out as the headline and
    /// excluded from `apps`. Summing it alongside the per-app rows double-counts every item
    /// (ADR-0003) — the trap that produced a wrong 404,894-item total on first read.
    public static func build(from rows: [PipelineCompletenessReport], updaterRunning: Bool) -> IndexStatus {
        let byPipeline = Dictionary(grouping: rows, by: \.pipeline)

        let pipelines = byPipeline.map { pipeline, rows -> PipelineProgress in
            let aggregate = rows.first(where: \.isAggregate)
            let apps = rows
                .filter { !$0.isAggregate }
                .map { AppProgress(bundleID: $0.bundleID, completeness: $0.completeness, eligibleItems: $0.eligibleItems) }
                .sorted { $0.completeness < $1.completeness }

            let derived = weightedMean(of: apps)
            return PipelineProgress(
                pipeline: pipeline,
                completeness: aggregate?.completeness ?? derived.completeness,
                eligibleItems: aggregate?.eligibleItems ?? derived.items,
                reportDate: rows.compactMap(\.reportDate).max(),
                apps: apps,
                headlineIsDerived: aggregate == nil
            )
        }
        .sorted { $0.completeness < $1.completeness }

        return IndexStatus(
            pipelines: pipelines,
            reportDate: rows.compactMap(\.reportDate).max(),
            updaterRunning: updaterRunning
        )
    }

    private static func weightedMean(of apps: [AppProgress]) -> (completeness: Double, items: Int) {
        let items = apps.reduce(0) { $0 + $1.eligibleItems }
        guard items > 0 else { return (0, 0) }
        let done = apps.reduce(0.0) { $0 + $1.completeness * Double($1.eligibleItems) }
        return (done / Double(items), items)
    }
}
