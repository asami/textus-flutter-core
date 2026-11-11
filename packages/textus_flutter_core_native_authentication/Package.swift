// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "TextusNativeAuthenticationContracts",
    platforms: [.macOS(.v10_15)],
    products: [.library(name: "AuthenticationContracts", targets: ["AuthenticationContracts"])],
    targets: [
        .target(
            name: "AuthenticationContracts",
            path: "ios/Classes",
            exclude: ["TextusFlutterCoreNativeAuthenticationPlugin.swift"],
            sources: ["CredentialStorePolicy.swift", "AuthenticationCredentialStore.swift"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(name: "AuthenticationContractTests", dependencies: ["AuthenticationContracts"], path: "Tests")
    ]
)
