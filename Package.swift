// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BatteryToolkit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "BatteryToolkit",
            targets: ["BatteryToolkit"]
        )
    ],
    targets: [
        .target(
            name: "BatteryToolkit",
            dependencies: [
                "SecCodeEx",
                "NSXPCConnectionAuditToken",
                "IOPMPrivate",
                "MachTaskSelf",
                "SMCParamStruct"
            ],
            path: "Sources",
            exclude: [
                "Modules",
                "me.mhaeuser.batterytoolkitd/Info.plist",
                "me.mhaeuser.batterytoolkitd/me.mhaeuser.batterytoolkitd.plist"
            ],
            sources: [
                "BatteryToolkit",
                "Common",
                "Libraries",
                "me.mhaeuser.batterytoolkitd"
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .target(
            name: "SecCodeEx",
            path: "Sources/Modules/SecCodeEx",
            publicHeadersPath: "."
        ),
        .target(
            name: "NSXPCConnectionAuditToken",
            path: "Sources/Modules/NSXPCConnectionAuditToken",
            publicHeadersPath: "."
        ),
        .target(
            name: "IOPMPrivate",
            path: "Sources/Modules/IOPMPrivate",
            publicHeadersPath: "."
        ),
        .target(
            name: "MachTaskSelf",
            path: "Sources/Modules/MachTaskSelf",
            publicHeadersPath: "."
        ),
        .target(
            name: "SMCParamStruct",
            path: "Sources/Modules/SMCParamStruct",
            publicHeadersPath: "."
        )
    ]
)
