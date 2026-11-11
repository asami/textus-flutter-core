// swift-tools-version: 5.7
import PackageDescription

// Foundation contracts and native CAF host tests; CocoaPods registers the Flutter iOS plugin.
let package = Package(
    name: "TextusIosAudioContracts",
    products: [.library(name: "AudioContracts", targets: ["AudioContracts"])],
    targets: [
        .target(
            name: "AudioContracts",
            path: "ios/Classes",
            exclude: [
                "TextusFlutterCoreIosAudioPlugin.swift", "IosAudioRecording.swift",
                "IosAudioPlayback.swift", "IosSavedAudioTranscriber.swift"
            ],
            sources: ["CanonicalPcmWaveAudio.swift", "AudioOperationOwner.swift", "PcmAudioFileReader.swift"],
            linkerSettings: [.linkedFramework("AVFoundation", .when(platforms: [.macOS]))]
        ),
        .testTarget(name: "AudioContractTests", dependencies: ["AudioContracts"], path: "Tests")
    ]
)
