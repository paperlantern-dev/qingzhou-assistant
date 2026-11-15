// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Qingzhou",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QingzhouApp", targets: ["QingzhouApp"]),
        .executable(name: "MockWeChat", targets: ["MockWeChat"]),
    ],
    targets: [
        .target(name: "QingzhouCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "QingzhouApp",
            dependencies: ["QingzhouCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(name: "MockWeChat", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "QingzhouCoreTests",
            dependencies: ["QingzhouCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
