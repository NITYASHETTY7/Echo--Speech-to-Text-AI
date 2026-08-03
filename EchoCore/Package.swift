// swift-tools-version: 5.9
//
//  Package.swift
//  EchoCore
//
//  Standalone Swift Package containing all reusable business logic for Echo.
//  The Echo app target depends on this package; the EchoTests target imports
//  it with @testable access.
//
//  Platforms mirror the app target: iOS 17+.
//

import PackageDescription

let package = Package(
    name: "EchoCore",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "EchoCore",
            targets: ["EchoCore"]
        ),
    ],
    targets: [
        .target(
            name: "EchoCore",
            path: "Sources/EchoCore",
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ]
)
