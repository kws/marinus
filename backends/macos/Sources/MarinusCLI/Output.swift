import Foundation

struct CommandResult: Codable, Equatable {
    var stdout = ""
    var stderr = ""
    var exitCode: Int32 = 0
}

func jsonText<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
}

func networkTable(_ networks: [WiFiNetwork]) -> String {
    var rows = [["SSID", "BSSID", "RSSI", "CH", "BAND", "WIDTH", "SEC", "FLAGS"]]
    for network in networks {
        let ssid = network.ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "<hidden>" : network.ssid
        let bssid = network.bssid.isEmpty ? "-" : network.bssid
        rows.append([
            ssid, bssid, String(network.rssi), String(network.channel), network.channelBand,
            String(network.channelWidth), network.security,
            (network.current ? "C" : "") + (network.saved ? "S" : ""),
        ])
    }
    let widths = (0..<7).map { column in rows.map { $0[column].unicodeScalars.count }.max()! }
    return rows.map { row in
        (0..<7).map { column in
            row[column] + String(repeating: " ", count: widths[column] - row[column].unicodeScalars.count + 2)
        }.joined() + row[7]
    }.joined(separator: "\n") + "\n"
}

private struct ConnectionStatus: Encodable { let connected = false }
private struct PasswordOutput: Encodable {
    let ssid: String
    let found: Bool
    let password: String?
}

func executeCommand(
    _ command: CLICommand,
    version: String,
    scan: (ScanMode) throws -> [WiFiNetwork] = scanNetworks,
    password: (String) throws -> String = keychainPassword,
    surveyScan: (CLICommand) -> [String: Any] = scanContract
) -> CommandResult {
    do {
        switch command.kind {
        case .help: return CommandResult(stdout: usage)
        case .version: return CommandResult(stdout: "marinus \(version)\n")
        case .interfaces:
            let value = macInterfaces()
            let items = value["interfaces"] as? [[String: Any]] ?? []
            return CommandResult(stdout: command.asJSON ? try contractJSON(value) : "INTERFACE\n" + items.map { $0["id"] as! String }.joined(separator: "\n") + "\n")
        case .watch:
            return CommandResult(stderr: "watch is run by the CLI coordinator\n", exitCode: 2)
        case .scan:
            if !command.legacy {
                let value = surveyScan(command)
                let failed = (value["scan"] as? [String: Any])?["status"] as? String == "failed"
                return CommandResult(stdout: command.asJSON ? try contractJSON(value) : contractTable(value), exitCode: failed ? 1 : 0)
            }
            let networks = try scan(command.scanMode)
            // Foundation pretty-prints an empty array across multiple lines;
            // retain the original CLI's empty-list output.
            let output = command.asJSON
                ? (networks.isEmpty ? "[]\n" : try jsonText(networks))
                : networkTable(networks)
            return CommandResult(stdout: output)
        case .info:
            let networks = try scan(command.scanMode)
            guard let current = networks.first(where: { $0.current }) else {
                return CommandResult(stdout: command.asJSON ? try jsonText(ConnectionStatus()) : "not connected to a Wi-Fi network\n")
            }
            return CommandResult(stdout: command.asJSON ? try jsonText(current) : networkTable([current]))
        case .password:
            let ssid = command.ssid!
            let value = try password(ssid)
            if command.asJSON {
                return CommandResult(stdout: try jsonText(PasswordOutput(
                    ssid: ssid, found: !value.isEmpty, password: value.isEmpty ? nil : value
                )))
            }
            if value.isEmpty { return CommandResult(stderr: "no saved password for \(ssid)\n", exitCode: 2) }
            return CommandResult(stdout: value + "\n")
        }
    } catch {
        return CommandResult(stderr: "error: \(command.kind.rawValue): \(error)\n", exitCode: 1)
    }
}
