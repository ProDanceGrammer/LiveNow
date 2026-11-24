// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "livenow_clipboard",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "livenow-clipboard", targets: ["livenow_clipboard"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "livenow_clipboard",
            dependencies: [],
            resources: []
        )
    ]
)
