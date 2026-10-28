// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudyTable",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "StudyTable", targets: ["StudyTable"])],
    targets: [
        // USFM parsing and the compact Scripture pack format. Shared by the app,
        // the pack builder, and the tests so all three agree byte for byte.
        .target(name: "StudyTableCore"),
        .executableTarget(
            name: "StudyTable",
            dependencies: ["StudyTableCore"],
            resources: [
                .copy("Resources/Scripture"),
                .copy("Resources/Study"),
                .copy("Resources/Confession"),
                .copy("Resources/Licenses"),
                .copy("Resources/Lexicon"),
                .copy("Resources/Interlinear"),
                .copy("Resources/Reference"),
                .copy("Resources/Materials"),
                .copy("Resources/PuritanLibrary")
            ]
        ),
        // Reproducible USFM -> compact pack generator (see scripts/build-scripture-packs.sh).
        .executableTarget(name: "BuildScriptureIndex", dependencies: ["StudyTableCore"]),
        .testTarget(
            name: "StudyTableTests",
            dependencies: ["StudyTable", "StudyTableCore"]
        )
    ]
)
