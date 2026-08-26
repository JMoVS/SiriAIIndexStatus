import Foundation

/// What one app got through between two checkpoints.
public struct AppDelta: Sendable, Hashable, Codable, Identifiable {
    public let bundleID: String
    /// Change in the fraction complete, as a fraction (0.014 = 1.4 percentage points).
    public let completenessChange: Double
    public let indexedItemsChange: Int
    public let eligibleItemsChange: Int
    /// The app carried no row in the earlier report — its whole count is new, not progress.
    public let isNew: Bool

    public var id: String { bundleID }

    public init(
        bundleID: String,
        completenessChange: Double,
        indexedItemsChange: Int,
        eligibleItemsChange: Int,
        isNew: Bool
    ) {
        self.bundleID = bundleID
        self.completenessChange = completenessChange
        self.indexedItemsChange = indexedItemsChange
        self.eligibleItemsChange = eligibleItemsChange
        self.isNew = isNew
    }

    public var hasMovement: Bool { indexedItemsChange != 0 || eligibleItemsChange != 0 }
}

/// What one pipeline got through between its last two reports.
///
/// Both figures are needed and neither substitutes for the other: the item count is the work
/// actually done, while the percentage also moves when the eligible set grows. An indexer that
/// embedded 3,000 items while 4,000 new ones arrived did a day's work and went *backwards* in
/// percent, and a display carrying only the percentage would call that a regression.
public struct PipelineDelta: Sendable, Hashable, Codable, Identifiable {
    public let pipeline: String
    public let previousDate: Date
    public let currentDate: Date
    /// Both ends, not just the difference: the panel shows `49.6% → 52.6%` rather than a change in
    /// percentage points, because "points" is jargon and a lone `+3.0` beside a percentage reads
    /// as a percentage of a percentage.
    public let previousCompleteness: Double
    public let currentCompleteness: Double
    public let indexedItemsChange: Int
    public let eligibleItemsChange: Int
    public let apps: [AppDelta]

    public var id: String { pipeline }

    public init(
        pipeline: String,
        previousDate: Date,
        currentDate: Date,
        previousCompleteness: Double,
        currentCompleteness: Double,
        indexedItemsChange: Int,
        eligibleItemsChange: Int,
        apps: [AppDelta]
    ) {
        self.pipeline = pipeline
        self.previousDate = previousDate
        self.currentDate = currentDate
        self.previousCompleteness = previousCompleteness
        self.currentCompleteness = currentCompleteness
        self.indexedItemsChange = indexedItemsChange
        self.eligibleItemsChange = eligibleItemsChange
        self.apps = apps
    }

    public var completenessChange: Double { currentCompleteness - previousCompleteness }

    /// Time between the two reports — the "per day" the figures are actually per.
    public var span: TimeInterval { currentDate.timeIntervalSince(previousDate) }

    public var hasMovement: Bool { indexedItemsChange != 0 || eligibleItemsChange != 0 }

    public func app(_ bundleID: String) -> AppDelta? {
        apps.first { $0.bundleID == bundleID }
    }

    /// Apps that moved, most work done first.
    public var movers: [AppDelta] {
        apps.filter(\.hasMovement).sorted { abs($0.indexedItemsChange) > abs($1.indexedItemsChange) }
    }
}

/// Progress across every pipeline since each one's previous report.
public struct IndexDelta: Sendable, Hashable, Codable {
    public let pipelines: [PipelineDelta]

    public init(pipelines: [PipelineDelta]) {
        self.pipelines = pipelines
    }

    public subscript(pipeline: String) -> PipelineDelta? {
        pipelines.first { $0.pipeline == pipeline }
    }

    public var isEmpty: Bool { pipelines.isEmpty }

    /// The widest span any pipeline was measured over — what "since the last report" covers.
    public var longestSpan: TimeInterval? { pipelines.map(\.span).max() }

    /// Compare the newest observation in `history` against the newest earlier one.
    ///
    /// Baselines are picked per pipeline rather than once for the whole log. Pipelines are written
    /// by separate jobs and do not all move on the same day; a single global baseline would report
    /// "no change" for every pipeline that missed the latest write, which is a statement about the
    /// report schedule rather than about indexing.
    public static func latest(in history: [IndexObservation]) -> IndexDelta? {
        guard let current = history.last, history.count > 1 else { return nil }
        let earlier = history.dropLast()

        let deltas = current.status.pipelines.compactMap { pipeline -> PipelineDelta? in
            guard let currentDate = pipeline.reportDate else { return nil }
            // Strictly earlier by at least a second: a date read back off disk has lost its
            // fractional part (`HistoryStore.isSameCheckpoint`), so `<` alone would treat a
            // re-read of the current checkpoint as its own predecessor and report a day's work as
            // "no change in the last half second".
            let baseline = earlier.reversed().lazy.compactMap { observation in
                observation.status.pipelines.first {
                    $0.pipeline == pipeline.pipeline
                        && ($0.reportDate.map { currentDate.timeIntervalSince($0) >= 1 } ?? false)
                }
            }.first
            guard let baseline, let previousDate = baseline.reportDate else { return nil }

            return PipelineDelta(
                pipeline: pipeline.pipeline,
                previousDate: previousDate,
                currentDate: currentDate,
                previousCompleteness: baseline.completeness,
                currentCompleteness: pipeline.completeness,
                indexedItemsChange: pipeline.indexedItems - baseline.indexedItems,
                eligibleItemsChange: pipeline.eligibleItems - baseline.eligibleItems,
                apps: appDeltas(from: baseline, to: pipeline)
            )
        }

        return deltas.isEmpty ? nil : IndexDelta(pipelines: deltas)
    }

    private static func appDeltas(from baseline: PipelineProgress, to current: PipelineProgress) -> [AppDelta] {
        let before = Dictionary(baseline.apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        return current.apps.map { app in
            guard let was = before[app.bundleID] else {
                return AppDelta(
                    bundleID: app.bundleID,
                    completenessChange: 0,
                    indexedItemsChange: app.indexedItems,
                    eligibleItemsChange: app.eligibleItems,
                    isNew: true
                )
            }
            return AppDelta(
                bundleID: app.bundleID,
                completenessChange: app.completeness - was.completeness,
                indexedItemsChange: app.indexedItems - was.indexedItems,
                eligibleItemsChange: app.eligibleItems - was.eligibleItems,
                isNew: false
            )
        }
    }
}
