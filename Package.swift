// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FLSNetworking",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "FLSNetworking", targets: ["FLSNetworking"])],
    dependencies: [
        // Keep Swift 6.0 compatibility; newer Alamofire minors raise the tools requirement.
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMinor(from: "5.10.2"))
    ],
    targets: [
        .target(name: "FLSNetworking", dependencies: [.product(name: "Alamofire", package: "Alamofire")]),
        .testTarget(name: "FLSNetworkingTests", dependencies: ["FLSNetworking"])
    ],
    swiftLanguageModes: [.v6]
)
