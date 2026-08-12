import XCTest
@testable import SiriIndexCore

final class ReportDecodingTests: XCTestCase {
    /// Build an archive shaped like Apple's: root is an NSArray of objects whose archived class
    /// name is `CSPipelineCompletenessReport`, which we do not link against.
    private func makeArchive(_ rows: [PipelineCompletenessReport]) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName("CSPipelineCompletenessReport", for: PipelineCompletenessReport.self)
        archiver.encode(rows as NSArray, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    func testDecodesRowsArchivedUnderApplesClassName() throws {
        let date = Date(timeIntervalSinceReferenceDate: 808_142_663)
        let data = try makeArchive([
            PipelineCompletenessReport(
                pipeline: "Embedding", bundleID: "all",
                completeness: 0.487, heuristicScore: 0.487,
                eligibleItems: 202_447, reportDate: date
            ),
            PipelineCompletenessReport(
                pipeline: "Embedding", bundleID: "com.apple.mail",
                completeness: 0.261, heuristicScore: 0.261,
                eligibleItems: 118_195, reportDate: date
            ),
        ])

        let rows = try ReportLoader.decode(archive: data, source: URL(fileURLWithPath: "/dev/null"))

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].pipeline, "Embedding")
        XCTAssertEqual(rows[0].bundleID, "all")
        XCTAssertEqual(rows[0].completeness, 0.487, accuracy: 0.0001)
        XCTAssertEqual(rows[0].eligibleItems, 202_447)
        XCTAssertEqual(rows[0].reportDate, date)
        XCTAssertTrue(rows[0].isAggregate)
        XCTAssertFalse(rows[1].isAggregate)
    }

    func testRejectsNonReportArchive() throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: ["not" as NSString: "a report" as NSString] as NSDictionary,
            requiringSecureCoding: true
        )
        XCTAssertThrowsError(try ReportLoader.decode(archive: data, source: URL(fileURLWithPath: "/dev/null")))
    }

    func testMissingDirectoryIsDistinguishedFromDeniedDirectory() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        XCTAssertThrowsError(try ReportLoader.loadAll(from: missing)) { error in
            guard let error = error as? ReportLoader.LoadError else { return XCTFail("wrong type") }
            XCTAssertFalse(error.isPermissionDenied, "absence must not prompt for Full Disk Access")
        }
    }

    /// The TCC path the app actually hits on first launch: directory present, read refused.
    func testUnreadableDirectoryIsReportedAsPermissionDenied() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("denied-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)

        // Running as root would defeat the mode bits and make this vacuous.
        try XCTSkipIf(getuid() == 0, "root bypasses directory permissions")

        XCTAssertThrowsError(try ReportLoader.loadAll(from: directory)) { error in
            guard let error = error as? ReportLoader.LoadError else { return XCTFail("wrong type") }
            XCTAssertTrue(error.isPermissionDenied)
        }
    }
}
