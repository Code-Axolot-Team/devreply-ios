// swift-tools-version: 6.0
// DevReply iOS SDK: the whole stack in Swift + SwiftUI (spec 05). No dependencies.
import PackageDescription

let package = Package(
    name: "DevReply",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DevReply", targets: ["DevReply"]),
    ],
    targets: [
        .target(
            name: "DevReply",
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
                .copy("Resources/Fonts"),
                .process("Resources/Icons.xcassets"),
            ]
        ),
        .testTarget(name: "DevReplyTests", dependencies: ["DevReply"]),
    ]
)
