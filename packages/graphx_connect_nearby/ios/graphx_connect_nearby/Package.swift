// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "graphx_connect_nearby",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "graphx-connect-nearby", targets: ["graphx_connect_nearby"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Pinned for reproducible plugin builds. Update deliberately after
        // validating iOS <-> Android discovery and payload exchange.
        .package(
            name: "NearbyConnections",
            url: "https://github.com/google/nearby.git",
            revision: "caca0367a2d5021e381abb286cc642bf8fb8548e"
        )
    ],
    targets: [
        .target(
            name: "graphx_connect_nearby",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "NearbyConnections", package: "NearbyConnections")
            ]
        )
    ]
)
