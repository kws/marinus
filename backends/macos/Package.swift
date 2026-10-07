// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Marinus",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "marinus", targets: ["MarinusCLI"])],
    targets: [
        .executableTarget(name: "MarinusCLI"),
    ]
)
