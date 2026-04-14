// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "NewsMappingKit",
  platforms: [
    .macOS(.v14)
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-argument-parser",
      from: "1.7.1"
    )
  ],
  targets: [
    .executableTarget(
      name: "NewsMappingKit",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ]
    ),
    .testTarget(
      name: "NewsMappingKitTests",
      dependencies: ["NewsMappingKit"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
