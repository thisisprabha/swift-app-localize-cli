import Foundation

@main
struct I18NCLI {
    static func main() async {
        let rawArgs = CommandLine.arguments
        let args = Array(rawArgs.dropFirst())

        do {
            if args.count == 3, args.first != "extract", args.first != "translate" {
                // Legacy mode: i18n-cli <projectRoot> <baseLang> <targetLangs>
                try await TranslateCommand.run(
                    projectRoot: args[0],
                    baseLang: args[1],
                    targetLangsCSV: args[2]
                )
                return
            }

            guard let subcommand = args.first else {
                throw UsageError.invalidArguments
            }

            switch subcommand {
            case "translate":
                guard args.count == 4 else { throw UsageError.invalidArguments }
                try await TranslateCommand.run(
                    projectRoot: args[1],
                    baseLang: args[2],
                    targetLangsCSV: args[3]
                )
            case "extract":
                try await ExtractCommand.run(args: Array(args.dropFirst()))
            default:
                throw UsageError.invalidArguments
            }
        } catch let error as UsageError {
            fputs(error.usage + "\n", stderr)
            exit(2)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

enum UsageError: Error {
    case invalidArguments

    var usage: String {
        """
        Usage:
          i18n-cli translate <projectRoot> <baseLang> <targetLangs>
          i18n-cli extract <projectRoot> <baseLang> [--apply] [--dry-run] [--key-prefix <prefix>] [--report <path>] [--include <csv>] [--exclude <csv>] [--overwrite-existing] [--no-skip-keys] [--stringsdict <auto|report>]

        Legacy:
          i18n-cli <projectRoot> <baseLang> <targetLangs>

        Examples:
          i18n-cli translate /path/to/App en fr,de,es
          i18n-cli extract /path/to/App en --key-prefix app
          i18n-cli extract /path/to/App en --apply
          i18n-cli extract /path/to/App en --stringsdict report
        """
    }
}
