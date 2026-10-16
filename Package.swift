// swift-tools-version: 6.0
// The manifest lives at the repository root so apps can depend on the repo URL;
// all code lives under kit/.
import PackageDescription

let package = Package(
    name: "HopeaLookKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "HopeaLookKit", targets: ["HopeaLookKit"]),
        .executable(name: "hopea-look", targets: ["hopea-look"]),
    ],
    targets: [
        .target(name: "HopeaLookKit", path: "kit/Sources/HopeaLookKit"),
        .executableTarget(name: "hopea-look", dependencies: ["HopeaLookKit"], path: "kit/Sources/hopea-look"),
        .testTarget(name: "HopeaLookKitTests", dependencies: ["HopeaLookKit"], path: "kit/Tests/HopeaLookKitTests"),
    ]
)
