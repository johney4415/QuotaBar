// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "quota-bar", targets: ["QuotaBar"]),
    ],
    targets: [
        .executableTarget(name: "QuotaBar"),
        .testTarget(name: "QuotaBarTests", dependencies: ["QuotaBar"]),
    ],
    swiftLanguageModes: [.v5]
)
