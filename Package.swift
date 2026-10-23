// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OhMyUsage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "OhMyUsage",
            targets: ["OhMyUsage"]
        )
    ],
    targets: [
        .target(
            name: "OhMyUsageDomain"
        ),
        .target(
            name: "OhMyUsageInfrastructure",
            dependencies: ["OhMyUsageDomain"]
        ),
        .target(
            name: "OhMyUsageProviders",
            dependencies: ["OhMyUsageDomain"]
        ),
        .target(
            name: "OhMyUsageApplication",
            dependencies: ["OhMyUsageDomain"]
        ),
        .target(
            name: "OhMyUsagePresentation",
            dependencies: ["OhMyUsageDomain"]
        ),
        .executableTarget(
            name: "OhMyUsage",
            dependencies: [
                "OhMyUsageDomain",
                "OhMyUsageInfrastructure",
                "OhMyUsageProviders",
                "OhMyUsageApplication",
                "OhMyUsagePresentation"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OhMyUsageTests",
            dependencies: [
                "OhMyUsage",
                "OhMyUsageDomain",
                "OhMyUsageInfrastructure",
                "OhMyUsageProviders",
                "OhMyUsageApplication",
                "OhMyUsagePresentation"
            ],
            exclude: [
                "Fixtures"
            ]
        )
    ]
)
