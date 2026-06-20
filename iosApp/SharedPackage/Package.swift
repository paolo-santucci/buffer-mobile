// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SharedPackage",
    products: [
        .library(name: "SharedPackage", targets: ["shared"])
    ],
    targets: [
        .binaryTarget(
            name: "shared",
            path: "../shared/build/XCFrameworks/release/shared.xcframework"
        )
    ]
)
