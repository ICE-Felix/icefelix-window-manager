// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to
// build this package.

import PackageDescription

let package = Package(
  name: "icefelix_window_manager",
  platforms: [
    .macOS("10.15")
  ],
  products: [
    .library(name: "icefelix-window-manager", targets: ["icefelix_window_manager"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "icefelix_window_manager",
      dependencies: []
    )
  ]
)
