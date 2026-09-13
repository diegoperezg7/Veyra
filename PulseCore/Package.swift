// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "PulseCore", platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v15)], products: [.library(name: "PulseCore", targets: ["PulseCore"])], targets: [.target(name: "PulseCore"), .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore"])])
