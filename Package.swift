// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "unPiNetworking",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "unPiNetworking",
            targets: ["unPiNetworking"]),
    ],
    targets: [
        .target(
            name: "unPiNetworking"),
        .testTarget(
            name: "unPiNetworkingTests",
            dependencies: ["unPiNetworking"]
        )])
