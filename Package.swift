// swift-tools-version: 6.2

import Foundation
import PackageDescription

// The override lets developers compile/test the D-Bus transport on macOS with libdbus installed.
#if os(Linux)
  let buildKDE = true
#else
  let buildKDE = ProcessInfo.processInfo.environment["REFLEX_BUILD_KDE"] == "1"
#endif

// Portable behavior tests run on both macOS and Linux.
var targets: [Target] = [
  .target(name: "ReflexWMCore", dependencies: [.product(name: "TOML", package: "swift-toml")]),
  .target(name: "ReflexWMKDECore", dependencies: ["ReflexWMCore"]),
  .testTarget(name: "ReflexWMKDECoreTests", dependencies: ["ReflexWMKDECore"]),
]
#if os(macOS)
  targets.append(.target(name: "ReflexWMMacSupport", dependencies: ["ReflexWMCore"]))
#endif
if buildKDE {
  targets.append(
    .systemLibrary(
      name: "CDBus", pkgConfig: "dbus-1", providers: [.apt(["libdbus-1-dev"]), .brew(["dbus"])]))
  targets.append(
    .executableTarget(name: "ReflexWMKDE", dependencies: ["ReflexWMKDECore", "CDBus"]))
  targets.append(.testTarget(name: "ReflexWMKDETests", dependencies: ["ReflexWMKDE"]))
} else {
  targets.append(
    .executableTarget(name: "ReflexWM", dependencies: ["ReflexWMCore", "ReflexWMMacSupport"]))
}
var coreTestDependencies: [Target.Dependency] = ["ReflexWMCore"]
#if os(macOS)
  coreTestDependencies.append("ReflexWMMacSupport")
#endif
targets.append(.testTarget(name: "ReflexWMCoreTests", dependencies: coreTestDependencies))

let package = Package(
  name: "reflex-wm",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "ReflexWMCore", targets: ["ReflexWMCore"]),
    .executable(
      name: buildKDE ? "reflex-wm-kde" : "reflex-wm",
      targets: [buildKDE ? "ReflexWMKDE" : "ReflexWM"]),
  ],
  dependencies: [.package(url: "https://github.com/mattt/swift-toml.git", from: "2.0.0")],
  targets: targets
)
