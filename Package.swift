// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacAlphaTrack",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macalphatrack", targets: ["macalphatrack"]),
        .library(name: "AlphaTrackKit", targets: ["AlphaTrackKit"]),
    ],
    targets: [
        // Pure protocol knowledge: USB ids, raw command encoders/decoders, Native-mode MIDI map.
        // No I/O here so it can be unit-tested without hardware.
        .target(name: "AlphaTrackKit"),
        // The daemon / CLI: USB transport (IOUSBHost), CoreMIDI virtual ports, subcommands.
        .executableTarget(
            name: "macalphatrack",
            dependencies: ["AlphaTrackKit"],
            linkerSettings: [.linkedFramework("IOUSBHost"), .linkedFramework("IOKit"), .linkedFramework("CoreMIDI")]
        ),
        .testTarget(
            name: "AlphaTrackKitTests",
            dependencies: ["AlphaTrackKit"]
        ),
    ]
)
