// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "NewsMappingKit",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(
      name: "NewsMappingCore",
      targets: ["NewsMappingCore"]
    ),
    .executable(
      name: "NewsMappingKit",
      targets: ["NewsMappingKit"]
    ),
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-argument-parser",
      from: "1.7.1"
    )
  ],
  targets: [
    .target(name: "NewsMappingCore"),
    .executableTarget(
      name: "NewsMappingKit",
      dependencies: [
        "NewsMappingCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ]
    ),
    .testTarget(
      name: "NewsMappingKitTests",
      dependencies: ["NewsMappingCore"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
