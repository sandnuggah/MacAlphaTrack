// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacAlphaTrack",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macalphatrack", targets: ["macalphatrack"]),
        .executable(name: "MacAlphaTrack", targets: ["MacAlphaTrackApp"]),
        .library(name: "AlphaTrackKit", targets: ["AlphaTrackKit"]),
        .library(name: "AlphaTrackDriver", targets: ["AlphaTrackDriver"]),
    ],
    targets: [
        // Pure protocol knowledge: USB ids, raw command encoders/decoders, Native-mode MIDI map.
        // No I/O here so it can be unit-tested without hardware.
        .target(name: "AlphaTrackKit"),
        // The driver proper: IOUSBHost transport, CoreMIDI virtual ports, the bridging
        // service, and the Live control-surface installer. Shared by the CLI and the app.
        .target(
            name: "AlphaTrackDriver",
            dependencies: ["AlphaTrackKit"],
            linkerSettings: [.linkedFramework("IOUSBHost"), .linkedFramework("IOKit"), .linkedFramework("CoreMIDI")]
        ),
        // Command-line tool: run the driver headless, dump reports, poke LEDs/LCD.
        .executableTarget(
            name: "macalphatrack",
            dependencies: ["AlphaTrackDriver", "AlphaTrackKit"]
        ),
        // Menu bar application. Bundled into MacAlphaTrack.app by Scripts/make-app.sh.
        .executableTarget(
            name: "MacAlphaTrackApp",
            dependencies: ["AlphaTrackDriver", "AlphaTrackKit"],
            linkerSettings: [.linkedFramework("ServiceManagement"), .linkedFramework("AppKit")]
        ),
        .testTarget(
            name: "AlphaTrackDriverTests",
            dependencies: ["AlphaTrackDriver"]
        ),
        .testTarget(
            name: "AlphaTrackKitTests",
            dependencies: ["AlphaTrackKit"]
        ),
    ]
)
