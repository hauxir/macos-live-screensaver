// swift-tools-version:5.9
import PackageDescription

// Only the pure logic lives here, so it can be built and tested on its own.
//
// The AppKit/ScreenSaver layer in Screensaver/ is deliberately outside
// Sources/: it cannot be exercised without a screensaver host, and building it
// is the Makefile's job. `make build` compiles both directories into the single
// module that becomes the .saver bundle.
let package = Package(
    name: "LiveScreensaverCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "LiveScreensaverCore"),
        .testTarget(
            name: "LiveScreensaverCoreTests",
            dependencies: ["LiveScreensaverCore"]
        ),
    ]
)
