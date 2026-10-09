import Darwin
import Foundation

// LaunchServices supplies the app identity needed by macOS privacy controls.
// The terminal and app run the same Swift executable. A private Unix socket
// returns stdout, stderr and status; passwords are never staged in a file.
private struct WorkerReply: Codable {
    let token: String
    let result: CommandResult
}

private var parentWatcher: DispatchSourceProcess?

func watchParent(_ pid: pid_t) {
    guard pid > 0 else { return }
    let watcher = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
    watcher.setEventHandler { exit(0) }
    watcher.resume()
    parentWatcher = watcher
    if kill(pid, 0) != 0 && errno == ESRCH { exit(0) }
}

private func unixAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    let bytes = Array(path.utf8) + [UInt8(0)]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        throw WiFiError.message("local socket path is too long")
    }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    return address
}

private func socketCall(_ address: inout sockaddr_un, _ call: (UnsafePointer<sockaddr>, socklen_t) -> Int32) -> Int32 {
    withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            call($0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}

private func writeData(_ data: Data, to descriptor: Int32) throws {
    var offset = 0
    while offset < data.count {
        let count = data.withUnsafeBytes {
            Darwin.write(descriptor, $0.baseAddress!.advanced(by: offset), data.count - offset)
        }
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw WiFiError.message("could not return the command result") }
        offset += count
    }
}

func appBundleURL(executablePath: String = CommandLine.arguments[0], override: String? = ProcessInfo.processInfo.environment["MARINUS_APP"]) throws -> URL {
    if let override {
        let bundle = URL(fileURLWithPath: override).standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: bundle.appendingPathComponent("Contents/MacOS/marinus").path) else {
            throw WiFiError.message("MARINUS_APP must point to the Swift Marinus.app bundle")
        }
        return bundle
    }
    let executable = URL(fileURLWithPath: executablePath).standardizedFileURL.resolvingSymlinksInPath()
    let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard bundle.pathExtension == "app",
          FileManager.default.isExecutableFile(atPath: bundle.appendingPathComponent("Contents/MacOS/marinus").path) else {
        throw WiFiError.message("Marinus.app was not found. Run make build and use dist/marinus, or set MARINUS_APP.")
    }
    return bundle
}

func appVersion() -> String {
    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { return version }
    if let url = try? appBundleURL(), let bundle = Bundle(url: url),
       let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { return version }
    return "dev"
}

func launchInApp(arguments: [String], timeout: TimeInterval, bundleURL: URL? = nil) throws -> CommandResult {
    let bundle = try bundleURL ?? appBundleURL()
    var template = Array("/tmp/marinus.XXXXXX".utf8CString)
    guard let directoryPointer = mkdtemp(&template) else {
        throw WiFiError.message("could not create a private command session")
    }
    let directory = String(cString: directoryPointer)
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = directory + "/socket"
    let listener = socket(AF_UNIX, SOCK_STREAM, 0)
    guard listener >= 0 else { throw WiFiError.message("could not create the local command socket") }
    defer { Darwin.close(listener) }
    _ = fcntl(listener, F_SETFD, FD_CLOEXEC)
    _ = fcntl(listener, F_SETFL, O_NONBLOCK)
    var address = try unixAddress(path)
    guard socketCall(&address, { Darwin.bind(listener, $0, $1) }) == 0,
          chmod(path, 0o600) == 0, listen(listener, 1) == 0 else {
        throw WiFiError.message("could not listen for the Marinus app")
    }
    let token = UUID().uuidString
    let process = Process()
    let launchErrors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [
        "-n", "-W", bundle.path, "--args",
        "--marinus-worker", path, token, String(getpid()),
    ] + arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = launchErrors
    try process.run()
    defer { if process.isRunning { process.terminate() } }

    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    var connection: Int32 = -1
    defer { if connection >= 0 { Darwin.close(connection) } }
    var response = Data()
    var buffer = [UInt8](repeating: 0, count: 65536)
    while ProcessInfo.processInfo.systemUptime < deadline {
        if connection < 0 {
            connection = accept(listener, nil, nil)
            if connection >= 0 {
                _ = fcntl(connection, F_SETFD, FD_CLOEXEC)
                _ = fcntl(connection, F_SETFL, O_NONBLOCK)
            } else if errno != EAGAIN && errno != EINTR {
                throw WiFiError.message("could not accept the Marinus app connection")
            }
        }
        if connection >= 0 {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(connection, $0.baseAddress!, $0.count) }
            if count > 0 {
                response.append(contentsOf: buffer.prefix(count))
                guard response.count <= 8 * 1024 * 1024 else {
                    throw WiFiError.message("Marinus returned an oversized result")
                }
                continue
            }
            if count == 0 {
                guard let reply = try? JSONDecoder().decode(WorkerReply.self, from: response), reply.token == token else {
                    throw WiFiError.message("Marinus exited without a valid command result")
                }
                return reply.result
            }
            if errno != EAGAIN && errno != EINTR {
                throw WiFiError.message("could not read the Marinus command result")
            }
        } else if !process.isRunning {
            let errorData = launchErrors.fileHandleForReading.readDataToEndOfFile()
            let detail = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw WiFiError.message(detail.isEmpty ? "Marinus could not be launched" : detail)
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    throw BackendFailure(code: "scan_timeout", message: "command timed out after \(timeout)s; check the macOS permission dialog")
}

func runWorker(_ arguments: [String]) -> Int32 {
    guard arguments.count >= 4, let pid = pid_t(arguments[2]), pid > 0 else { return 2 }
    let path = arguments[0]
    let token = arguments[1]
    watchParent(pid)
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return 1 }
    defer { Darwin.close(descriptor) }
    do {
        var address = try unixAddress(path)
        guard socketCall(&address, { Darwin.connect(descriptor, $0, $1) }) == 0 else { return 1 }
        let result: CommandResult
        do {
            let command = try parseCommand(Array(arguments.dropFirst(3)))
            result = executeCommand(command, version: appVersion())
        } catch {
            result = CommandResult(stderr: "\(error)\n", exitCode: 2)
        }
        try writeData(JSONEncoder().encode(WorkerReply(token: token, result: result)), to: descriptor)
        return result.exitCode
    } catch { return 1 }
}
