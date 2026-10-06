// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "QuickTileCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "QuickTileCore", targets: ["QuickTileCore"]), .executable(name: "quicktile-action-matrix", targets: ["ActionValidationTool"])],
    targets: [.target(name: "QuickTileCore"), .executableTarget(name: "ActionValidationTool", dependencies: ["QuickTileCore"]), .testTarget(name: "QuickTileCoreTests", dependencies: ["QuickTileCore"])],
    swiftLanguageModes: [.v5]
)
