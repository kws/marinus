import Darwin
import Foundation

func runSurveyCLI(_ command: CLICommand) throws -> Int32 {
    // Preserve existing captures before requesting radio or privacy access.
    var file: FileHandle?
    if let path = command.output {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw WiFiError.message("could not create a new capture: \(path)") }
        file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
    defer { try? file?.close() }
    signal(SIGINT) { _ in exit(130) }
    signal(SIGTERM) { _ in exit(130) }
    var interfaceID = command.interfaceID
    var index = 0
    repeat {
        let started = contractTimestamp()
        var arguments = ["scan", "--json", "--timeout", String(command.timeout)]
        if let interfaceID { arguments += ["--interface", interfaceID] }
        if command.cached { arguments.append("--cached") }
        let value: [String: Any]
        do {
            let result = try launchInApp(arguments: arguments, timeout: command.timeout)
            guard let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any] else {
                throw WiFiError.message("scanner returned an invalid result")
            }
            value = object
        } catch {
            let failure = error as? BackendFailure ?? BackendFailure(code: "backend_error", message: String(describing: error))
            value = scanEnvelope(interface: interfaceID ?? "auto", started: started, status: "failed", error: failure)
        }
        let json = try contractJSON(value, compact: command.kind == .watch)
        try file?.write(contentsOf: Data(json.utf8))
        FileHandle.standardOutput.write(Data((command.asJSON ? json : contractTable(value)).utf8))
        if (value["scan"] as? [String: Any])?["status"] as? String == "failed" { return 1 }
        interfaceID = (value["interface"] as? [String: Any])?["id"] as? String
        index += 1
        if command.kind != .watch || command.count.map({ index >= $0 }) == true { break }
        Thread.sleep(forTimeInterval: command.interval)
    } while true
    return 0
}
