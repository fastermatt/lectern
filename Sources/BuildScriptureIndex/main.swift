import Foundation
import StudyTableCore

// Usage: BuildScriptureIndex <source-dir> <output-dir> [--check] [--no-structure]
// <source-dir> holds USFM files plus translation.json. Output is deterministic:
// sorted keys, no timestamps, so a rebuild of unchanged input is byte-identical.
// --no-structure leaves section headings, parallel references and paragraph starts out.

let arguments = CommandLine.arguments.dropFirst()
let flags = arguments.filter { $0.hasPrefix("--") }
let paths = arguments.filter { !$0.hasPrefix("--") }
guard paths.count == 2 else {
    FileHandle.standardError.write(Data("usage: BuildScriptureIndex <source-dir> <output-dir> [--check] [--no-structure]\n".utf8))
    exit(64)
}
let source = URL(fileURLWithPath: paths[0], isDirectory: true)
let output = URL(fileURLWithPath: paths[1], isDirectory: true)

do {
    let pack = try ScripturePackBuilder.build(sourceDirectory: source, includeStructure: !flags.contains("--no-structure"))
    let verseTotal = pack.manifest.books.flatMap(\.verses).reduce(0, +)
    let stats = pack.stats
    let levels = stats.headingsByLevel.sorted { $0.key < $1.key }.map { "L\($0.key)=\($0.value)" }.joined(separator: " ")
    let structure = "headings \(stats.headings) [\(levels)], parallel lines \(stats.parallelLines) / refs \(stats.parallelReferences) "
        + "(unresolved \(stats.unresolvedReferences.count)), paragraph starts \(stats.paragraphStarts), dropped headings \(stats.droppedHeadings.count)"
    if !stats.unresolvedReferences.isEmpty { print("  unresolved references: \(stats.unresolvedReferences.sorted())") }
    for dropped in stats.droppedHeadings.sorted() { print("  dropped heading: \(dropped)") }
    if flags.contains("--check") {
        let stale = ScripturePackBuilder.drift(of: pack, in: output)
        if stale.isEmpty {
            print("\(pack.manifest.id): up to date (\(pack.books.count) books, \(verseTotal) verses; \(structure))")
        } else {
            print("\(pack.manifest.id): STALE files: \(stale.joined(separator: ", "))")
            exit(1)
        }
    } else {
        try ScripturePackBuilder.write(pack, to: output)
        print("\(pack.manifest.id): wrote \(pack.books.count) books, \(verseTotal) verses -> \(output.path)\n  \(structure)")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
