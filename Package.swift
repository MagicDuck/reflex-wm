// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "reflex-wm",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "ReflexWMCore", targets: ["ReflexWMCore"]),
    .executable(name: "reflex-wm", targets: ["ReflexWM"]),
  ],
  dependencies: [
    .package(url: "https://github.com/mattt/swift-toml.git", from: "2.0.0")
  ],
  targets: [
    .target(
      name: "ReflexWMCore",
      dependencies: [.product(name: "TOML", package: "swift-toml")]
    ),
    .executableTarget(
      name: "ReflexWM",
      dependencies: ["ReflexWMCore"]
    ),
    .testTarget(
      name: "ReflexWMCoreTests",
      dependencies: ["ReflexWMCore"]
    ),
  ]
)
