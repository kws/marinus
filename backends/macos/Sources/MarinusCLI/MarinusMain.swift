import Darwin
import Foundation

@main
struct MarinusMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--marinus-worker" {
            exit(runWorker(Array(arguments.dropFirst())))
        }
        let result: CommandResult
        do {
            let command = try parseCommand(arguments)
            if command.needsApp {
                if command.kind == .password && !command.noPromptHint {
                    let hint = "→ macOS may prompt for Keychain access to \(String(reflecting: command.ssid!))\n"
                    FileHandle.standardError.write(Data(hint.utf8))
                }
                result = try launchInApp(arguments: arguments, timeout: command.timeout)
            } else {
                result = executeCommand(command, version: appVersion())
            }
        } catch let error as CLIParseError {
            result = CommandResult(stderr: "\(error)\n", exitCode: 2)
        } catch {
            result = CommandResult(stderr: "error: \(error)\n", exitCode: 1)
        }
        FileHandle.standardOutput.write(Data(result.stdout.utf8))
        FileHandle.standardError.write(Data(result.stderr.utf8))
        exit(result.exitCode)
    }
}
