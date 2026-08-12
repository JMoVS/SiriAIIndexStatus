import Foundation

/// Reads the per-pipeline completeness reports CoreSpotlight writes for the current user.
public enum ReportLoader {
    /// `~/Library/Metadata/CoreSpotlight/PipelineCompletenessReporting`.
    ///
    /// Not sandbox-reachable: the app must ship unsandboxed (ADR-0001).
    public static var defaultDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Metadata/CoreSpotlight/PipelineCompletenessReporting", isDirectory: true)
    }

    public enum LoadError: Error, LocalizedError {
        /// The report directory is TCC-protected. Reading it needs Full Disk Access, which a
        /// freshly built bundle never has (ADR-0004).
        case permissionDenied(URL)
        case directoryMissing(URL)
        case directoryUnreadable(URL, underlying: Error)
        case notAnArchiveOfReports(URL)

        public var errorDescription: String? {
            switch self {
            case .permissionDenied(let url):
                return "Full Disk Access is required to read \(url.lastPathComponent)."
            case .directoryMissing(let url):
                return "\(url.lastPathComponent) does not exist yet."
            case .directoryUnreadable(let url, let underlying):
                return "Cannot read \(url.path): \(underlying.localizedDescription)"
            case .notAnArchiveOfReports(let url):
                return "\(url.lastPathComponent) is not a completeness-report archive"
            }
        }

        public var isPermissionDenied: Bool {
            if case .permissionDenied = self { return true }
            return false
        }
    }

    /// Every report row across every pipeline file, unaggregated.
    ///
    /// A single unreadable or unexpected file is skipped rather than failing the whole load — the
    /// set of pipelines is Apple's to change, and one new format should not blank the UI.
    public static func loadAll(from directory: URL = ReportLoader.defaultDirectory) throws -> [PipelineCompletenessReport] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            // TCC denial and plain absence are different problems with different fixes, and the
            // UI must not tell the user to grant access when the directory simply is not there.
            let nsError = error as NSError
            switch (nsError.domain, nsError.code) {
            case (NSCocoaErrorDomain, NSFileReadNoPermissionError),
                 (NSPOSIXErrorDomain, Int(EACCES)), (NSPOSIXErrorDomain, Int(EPERM)):
                throw LoadError.permissionDenied(directory)
            case (NSCocoaErrorDomain, NSFileReadNoSuchFileError), (NSPOSIXErrorDomain, Int(ENOENT)):
                throw LoadError.directoryMissing(directory)
            default:
                throw LoadError.directoryUnreadable(directory, underlying: error)
            }
        }

        return files
            .filter { $0.pathExtension == "plist" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { (try? load(contentsOf: $0)) ?? [] }
    }

    /// Decode one `completenessReport_<pipeline>.plist`.
    public static func load(contentsOf url: URL) throws -> [PipelineCompletenessReport] {
        let data = try Data(contentsOf: url)
        return try decode(archive: data, source: url)
    }

    /// Split out from `load(contentsOf:)` so tests can round-trip an archive without touching disk.
    public static func decode(archive data: Data, source: URL) throws -> [PipelineCompletenessReport] {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = true
        unarchiver.setClass(PipelineCompletenessReport.self, forClassName: "CSPipelineCompletenessReport")
        defer { unarchiver.finishDecoding() }

        let root = unarchiver.decodeObject(
            of: [NSArray.self, PipelineCompletenessReport.self, NSDate.self, NSString.self, NSNumber.self],
            forKey: NSKeyedArchiveRootObjectKey
        )

        guard let rows = root as? [PipelineCompletenessReport], !rows.isEmpty else {
            throw LoadError.notAnArchiveOfReports(source)
        }
        return rows
    }
}
