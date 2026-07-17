// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "codexbar-to-greptimedb",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(
      url: "https://github.com/steipete/CodexBar",
      revision: "5a0cbc07119ac04d998e2fd5267442ed9358fff0")
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .executableTarget(
      name: "codexbar-to-greptimedb",
      dependencies: [
        .product(name: "CodexBarCore", package: "CodexBar")
      ]
    ),
    .testTarget(
      name: "codexbar-to-greptimedbTests",
      dependencies: ["codexbar-to-greptimedb"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
