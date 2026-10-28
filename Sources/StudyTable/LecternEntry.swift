import Foundation
import SwiftUI

@main
enum LecternEntry {
    @MainActor static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--cli" {
            let response = await LecternCLI.run(Array(args.dropFirst()))
            let output = response.status == 0 ? FileHandle.standardOutput : FileHandle.standardError
            output.write(response.data)
            exit(response.status)
        }
        StudyTableApp.main()
    }
}
