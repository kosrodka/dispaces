// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Dispaces",
    platforms: [.macOS("26.0")],
    targets: [
        // Declarations for the one private, read-only CoreGraphics call we need.
        .target(
            name: "CGSPrivate",
            linkerSettings: [.linkedFramework("CoreGraphics")]
        ),
        // Pure logic: parsing, numbering, names, switch planning. Foundation only, fully unit-tested.
        .target(name: "SpacesCore"),
        // The app: AppKit glue.
        .executableTarget(
            name: "Dispaces",
            dependencies: ["SpacesCore", "CGSPrivate"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "SpacesCoreTests", dependencies: ["SpacesCore"]),
    ],
    swiftLanguageModes: [.v5]
)
