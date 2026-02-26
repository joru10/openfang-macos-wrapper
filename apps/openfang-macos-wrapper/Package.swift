// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenFangMacOSWrapper",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OpenFangWrapperApp", targets: ["OpenFangWrapperApp"]),
    ],
    targets: [
        .executableTarget(
            name: "OpenFangWrapperApp",
            path: "Sources/OpenFangWrapperApp"
        )
    ]
)
