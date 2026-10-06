// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "VoiceInputMacApp",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "VoiceInputMacApp", targets: ["VoiceInputMacApp"])
    ],
    dependencies: [
        .package(path: ".speech-swift")
    ],
    targets: [
        .executableTarget(
            name: "VoiceInputMacApp",
            dependencies: [
                .product(name: "SpeechVAD", package: ".speech-swift"),
                .product(name: "AudioCommon", package: ".speech-swift"),
            ],
            path: "VoiceInputMacApp/Sources",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
