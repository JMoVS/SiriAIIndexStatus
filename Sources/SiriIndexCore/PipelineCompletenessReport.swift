import Foundation

/// Decoded stand-in for Apple's private `CSPipelineCompletenessReport` (CoreSpotlight).
///
/// The on-disk reports are `NSKeyedArchiver` archives whose `$classname` is
/// `CSPipelineCompletenessReport` — a class we cannot link against. Rather than walking the
/// `$objects` UID graph by hand (which needs `CFKeyedArchiverUID`, not public API), we register
/// this type as the substitute class on the unarchiver. See ADR-0002.
@objc(SIISPipelineCompletenessReport)
public final class PipelineCompletenessReport: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    /// Pipeline identifier as Apple writes it, e.g. `Embedding`, `LSSR5EventsandordersUrgent`.
    public let pipeline: String
    /// Donating app's bundle id, or `all` for the pipeline-wide aggregate row (ADR-0003).
    public let bundleID: String
    /// Fraction complete, 0...1.
    public let completeness: Double
    /// Apple's heuristic score. Equal to `completeness` in every sample observed so far.
    public let heuristicScore: Double
    /// Items this pipeline considers in scope for this bundle id.
    public let eligibleItems: Int
    /// When the daemon last wrote this row. Reports refresh roughly daily, not live.
    public let reportDate: Date?

    public init(
        pipeline: String,
        bundleID: String,
        completeness: Double,
        heuristicScore: Double,
        eligibleItems: Int,
        reportDate: Date?
    ) {
        self.pipeline = pipeline
        self.bundleID = bundleID
        self.completeness = completeness
        self.heuristicScore = heuristicScore
        self.eligibleItems = eligibleItems
        self.reportDate = reportDate
    }

    public init?(coder: NSCoder) {
        guard let pipeline = coder.decodeObject(of: NSString.self, forKey: "pipeline") as String?,
              let bundleID = coder.decodeObject(of: NSString.self, forKey: "bundleID") as String?
        else { return nil }

        // Every scalar here is archived as an object reference to an NSNumber, not as an inline
        // primitive — `decodeInteger(forKey:)`/`decodeDouble(forKey:)` return 0 for all of them.
        self.pipeline = pipeline
        self.bundleID = bundleID
        self.completeness = coder.decodeObject(of: NSNumber.self, forKey: "pipelineCompleteness")?.doubleValue ?? 0
        self.heuristicScore = coder.decodeObject(
            of: NSNumber.self, forKey: "pipelineCompletenessHeuristicScore"
        )?.doubleValue ?? 0
        self.eligibleItems = coder.decodeObject(of: NSNumber.self, forKey: "eligibleItems")?.intValue ?? 0
        self.reportDate = coder.decodeObject(of: NSDate.self, forKey: "reportDate") as Date?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(pipeline as NSString, forKey: "pipeline")
        coder.encode(bundleID as NSString, forKey: "bundleID")
        coder.encode(NSNumber(value: completeness), forKey: "pipelineCompleteness")
        coder.encode(NSNumber(value: heuristicScore), forKey: "pipelineCompletenessHeuristicScore")
        coder.encode(NSNumber(value: eligibleItems), forKey: "eligibleItems")
        coder.encode(reportDate as NSDate?, forKey: "reportDate")
    }

    /// `all` is the pipeline-wide aggregate row, not a sibling of the per-app rows (ADR-0003).
    public static let aggregateBundleID = "all"

    public var isAggregate: Bool { bundleID == Self.aggregateBundleID }

    public override var description: String {
        "\(pipeline)/\(bundleID) \(completeness) of \(eligibleItems)"
    }
}
