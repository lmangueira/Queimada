// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "BluRayBurner",
    platforms: [.macOS(.v15)],
    targets: [
        // Framework-free core: models, view-models, service protocol, mock.
        // KTD1: no DiscRecording types past this boundary — fully testable in CI.
        .target(
            name: "BluRayBurnerCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The shipping app: SwiftUI shell + concrete DiscRecording-backed service.
        .executableTarget(
            name: "BluRayBurner",
            dependencies: ["BluRayBurnerCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("DiscRecording")]
        ),
        // U1 sandbox spike: throwaway diagnostic app, not shipped.
        .executableTarget(
            name: "SandboxBurnSpike",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("DiscRecording")]
        ),
        .testTarget(
            name: "BluRayBurnerCoreTests",
            dependencies: ["BluRayBurnerCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
