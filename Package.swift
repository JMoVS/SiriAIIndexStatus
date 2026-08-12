// swift-tools-version: 6.0
// ADR-0001: Swift 6 language mode, SwiftPM, SwiftUI MenuBarExtra, no third-party deps.
import PackageDescription

let package = Package(
    name: "SiriAIIndexStatus",
    platforms: [
        // 26.6 is the floor for a reason, not caution: the completeness reports this app exists to
        // read do not exist before it (ADR-0002). An older macOS builds a working app with nothing
        // to show.
        .macOS("26.6"),
    ],
    products: [
        // Shared by the menu bar app and the widget (ADR-0001).
        .library(name: "SiriIndexCore", targets: ["SiriIndexCore"]),
        .executable(name: "SiriAIIndexStatus", targets: ["SiriAIIndexStatus"]),
    ],
    targets: [
        .target(
            name: "SiriIndexCore",
            path: "Sources/SiriIndexCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SiriAIIndexStatus",
            dependencies: ["SiriIndexCore"],
            path: "Sources/SiriAIIndexStatus",
            // Generated from project.yml and consumed by Xcode, not SwiftPM (ADR-0005).
            exclude: ["Info.plist", "SiriAIIndexStatus.entitlements"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SiriAIIndexStatusTests",
            dependencies: ["SiriIndexCore"],
            path: "Tests/SiriAIIndexStatusTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
