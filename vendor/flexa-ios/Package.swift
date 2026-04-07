// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let env = ProcessInfo.processInfo.environment["FX_ENABLE_GLASS"]
let supportsGlass = (env == nil) || (env == "1")

let package = Package(
    name: "Flexa",
    defaultLocalization: LanguageTag("en"),
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "Flexa",
            targets: ["Flexa"]),
        .library(
            name: "FlexaCore",
            targets: ["FlexaCore"]),
        .library(
            name: "FlexaScan",
            targets: ["FlexaScan"]),
        .library(
            name: "FlexaLoad",
            targets: ["FlexaLoad"]),
        .library(
            name: "FlexaSpend",
            targets: ["FlexaSpend"]),
        .library(
            name: "FlexaUICore",
            targets: ["FlexaUICore"]),
        .library(
            name: "FlexaNetworking",
            targets: ["FlexaNetworking"])
    ],
    dependencies: [
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "3.0.0"),
        .package(url: "https://github.com/devicekit/DeviceKit.git", from: "5.5.0"),
        .package(url: "https://github.com/exyte/SVGView.git", from: "1.0.4"),
        .package(url: "https://github.com/hmlongco/Factory.git", from: "2.3.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "13.2.0"),
        .package(url: "https://github.com/Quick/Quick.git", from: "7.0.0"),
        .package(url: "https://github.com/vadymmarkov/Fakery.git", from: "5.1.0"),
        .package(url: "https://github.com/siteline/swiftui-introspect", from: "26.0.0"),
        .package(url: "https://github.com/ekscrypto/Base32.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "Flexa",
            dependencies: ["FlexaCore", "FlexaScan", "FlexaLoad", "FlexaSpend", "FlexaUICore"],
            path: "Sources"
        ),
        .testTarget(
            name: "FlexaTests",
            dependencies: ["FlexaCore", "Flexa"],
            path: "Tests"),
        .target(
            name: "FlexaCore",
            dependencies: [
                "FlexaNetworking",
                "Factory",
                "DeviceKit",
                "KeychainAccess",
                "FlexaUICore",
                "Base32",
                "SVGView",
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect")
            ],
            path: "FlexaCore/Sources",
            resources: [.process("Resources")],
            swiftSettings:
                supportsGlass ? [.define("FX_ENABLE_GLASS")] : []
            
        ),
        .testTarget(
            name: "FlexaCoreTests",
            dependencies: ["FlexaCore", "FlexaUICore", "Nimble", "Quick", "Fakery"],
            path: "FlexaCore/Tests"),
        .target(
            name: "FlexaUICore",
            dependencies: [
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect")
            ],
            path: "FlexaUICore/Sources",
            swiftSettings:
                supportsGlass ? [.define("FX_ENABLE_GLASS")] : []
            
        ),
        .testTarget(
            name: "FlexaUICoreTests",
            dependencies: [
                "FlexaUICore",
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect")
            ],
            path: "FlexaUICore/Tests"),
        .target(
            name: "FlexaScan",
            dependencies: ["FlexaCore", "FlexaUICore"],
            path: "FlexaScan/Sources",
            resources: [.process("Resources")]),
        .testTarget(
            name: "FlexaScanTests",
            dependencies: ["FlexaCore", "FlexaUICore", "FlexaScan"],
            path: "FlexaScan/Tests"),
        .target(
            name: "FlexaLoad",
            dependencies: ["FlexaCore"],
            path: "FlexaLoad/Sources"),
        .testTarget(
            name: "FlexaLoadTests",
            dependencies: ["FlexaCore", "FlexaLoad"],
            path: "FlexaLoad/Tests"),
        .target(
            name: "FlexaSpend",
            dependencies: ["FlexaCore", "FlexaUICore", "SVGView", "Factory", "Base32"],
            path: "FlexaSpend/Sources",
            resources: [.process("Resources")]),
        .testTarget(
            name: "FlexaSpendTests",
            dependencies: ["FlexaCore", "FlexaSpend", "FlexaUICore", "SVGView", "Nimble", "Quick", "Fakery"],
            path: "FlexaSpend/Tests"),
        .target(
            name: "FlexaNetworking",
            dependencies: ["Factory"],
            path: "FlexaNetworking/Sources"),
        .testTarget(
            name: "FlexaNetworkingTests",
            dependencies: ["FlexaNetworking", "Factory", "Nimble", "Quick", "Fakery"],
            path: "FlexaNetworking/Tests")
    ],
    swiftLanguageVersions: [.v5]
)
