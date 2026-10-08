// swift-tools-version: 5.9
import PackageDescription

// qUltraKotoro — superwhisper on steroids.
// Local speech-to-text, an emotional QuantTern encoding, and the app core for
// the iOS + macOS builds. This package is the shared brain; the app layers
// (KotoroIOS, KotoroMac) add SwiftUI + whichever local STT engine the device
// ships with.
let package = Package(
    name: "qUltraKotoro",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QuantTern", targets: ["QuantTern"]),
        .library(name: "KotoroCore", targets: ["KotoroCore"]),
    ],
    targets: [
        .target(name: "QuantTern"),
        .target(name: "KotoroCore", dependencies: ["QuantTern"]),
        .testTarget(name: "QuantTernTests", dependencies: ["QuantTern", "KotoroCore"]),
    ]
)
