// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TonnageCore",
    platforms: [
        .iOS("26.0"),
        .watchOS("26.0"),
        // macOS is declared only so the package can be compile-checked from the
        // command line (`swift build`). The shipping app runs on iOS / watchOS.
        .macOS("26.0")
    ],
    products: [
        .library(name: "TonnageCore", targets: ["TonnageCore"])
    ],
    targets: [
        .target(name: "TonnageCore"),
        .testTarget(name: "TonnageCoreTests", dependencies: ["TonnageCore"])
    ]
)
