// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SSHConsole",
    
    // I don't care, but NIOSS does.
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],

    products: [
        .library( name: "SSHConsole", targets: ["SSHConsole"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.0.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target( name: "SSHConsole",
                 dependencies: [ .product(name: "NIOSSH", package: "swift-nio-ssh")]),
        .testTarget( name: "SSHConsoleTests", dependencies: ["SSHConsole"]),
    ]
)
