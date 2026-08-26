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
        // Named apart from the Xcode app target on purpose. Both build the same sources, and while
        // they shared the name `SiriAIIndexStatus`, `xcodebuild -scheme SiriAIIndexStatus` resolved
        // to this plain executable and left `SiriAIIndexStatus.app` stale — a bundle that silently
        // kept shipping the previous build.
        .executable(name: "SiriAIIndexStatusMenuBar", targets: ["SiriAIIndexStatusMenuBar"]),
    ],
    targets: [
        .target(
            name: "SiriIndexCore",
            path: "Sources/SiriIndexCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SiriAIIndexStatusMenuBar",
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
