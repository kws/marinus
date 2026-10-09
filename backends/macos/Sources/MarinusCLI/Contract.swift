import CoreWLAN
import Foundation

// JSONSerialization emits explicit nulls, including identifiers masked by privacy controls.
let contractNull = NSNull()
let macBackend: [String: Any] = ["platform": "macos", "name": "corewlan", "backend_version": "0.1.0"]
let macCapabilities: [String: Any] = [
    "rssi_dbm": true, "noise_dbm": true, "strength_percent": false,
    "channel_width_mhz": true, "last_seen_resolution_ms": contractNull,
]

struct BackendFailure: Error, CustomStringConvertible {
    let code: String
    let message: String
    var description: String { message }
}

func contractTimestamp(_ date: Date = Date()) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

func contractJSON(_ value: Any, compact: Bool = false) throws -> String {
    let options: JSONSerialization.WritingOptions = compact ? [.sortedKeys] : [.sortedKeys, .prettyPrinted]
    return String(decoding: try JSONSerialization.data(withJSONObject: value, options: options), as: UTF8.self) + "\n"
}

func channelFrequency(number: Int?, band: String) -> Int? {
    guard let number, number > 0 else { return nil }
    switch band {
    case "2.4GHz": return number == 14 ? 2484 : (number <= 13 ? 2407 + number * 5 : nil)
    case "5GHz": return (182...196).contains(number) ? 4000 + number * 5 : 5000 + number * 5
    case "6GHz": return number == 2 ? 5935 : 5950 + number * 5
    default: return nil
    }
}

struct ContractNetwork {
    var ssid: String?
    var ssidData: Data?
    var bssid: String?
    var rssi: Int?
    var noise: Int?
    var channel: Int?
    var band: String
    var width: Int?
}

func contractObservation(_ network: ContractNetwork, currentBSSID: String?) -> [String: Any] {
    let normalized = normalizedBSSID(network.bssid)
    let current = normalizedBSSID(currentBSSID)
    return [
        "ssid": network.ssid as Any? ?? contractNull,
        "ssid_bytes_base64": network.ssidData?.base64EncodedString() as Any? ?? contractNull,
        "bssid": normalized.isEmpty ? contractNull : normalized as Any,
        "rssi_dbm": network.rssi.flatMap { $0 < 0 ? $0 : nil } as Any? ?? contractNull,
        "noise_dbm": network.noise.flatMap { $0 < 0 ? $0 : nil } as Any? ?? contractNull,
        "strength_percent": contractNull,
        "frequency_mhz": channelFrequency(number: network.channel, band: network.band) as Any? ?? contractNull,
        "channel_width_mhz": network.width.flatMap { $0 > 0 ? $0 : nil } as Any? ?? contractNull,
        "connected": normalized.isEmpty || current.isEmpty ? contractNull : (normalized == current) as Any,
        // CoreWLAN supplies no per-observation timestamp. Completion cannot prove freshness.
        "freshness": "unknown", "last_seen_age_ms": contractNull,
    ]
}

func scanEnvelope(interface: String, started: String, status: String,
                  observations: [[String: Any]] = [], error: BackendFailure? = nil) -> [String: Any] {
    ["contract_version": "0.1.0", "backend": macBackend,
     "interface": ["id": interface, "driver": contractNull], "capabilities": macCapabilities,
     "scan": ["status": status, "started_at": started,
              "completed_at": status == "failed" ? contractNull : contractTimestamp() as Any,
              "error": error.map { ["code": $0.code, "message": $0.message] } as Any? ?? contractNull],
     "observations": status == "failed" ? [] : observations]
}

func macInterfaces() -> [String: Any] {
    let items: [[String: Any]] = (CWWiFiClient.shared().interfaceNames() ?? []).sorted().map { name in
        ["id": name, "name": name, "driver": contractNull, "state": contractNull]
    }
    return ["contract_version": "0.1.0", "backend": macBackend, "interfaces": items, "error": contractNull]
}

func scanContract(_ command: CLICommand) -> [String: Any] {
    let started = contractTimestamp()
    var interfaceID = command.interfaceID ?? "auto"
    do {
        let names = (CWWiFiClient.shared().interfaceNames() ?? []).sorted()
        if command.interfaceID == nil && names.count > 1 {
            throw BackendFailure(code: "interface_unavailable", message: "Multiple Wi-Fi interfaces are available; select --interface.")
        }
        guard let name = command.interfaceID ?? names.first, names.contains(name),
              let interface = CWWiFiClient.shared().interface(withName: name) else {
            throw BackendFailure(code: "interface_unavailable", message: "No matching Wi-Fi interface is available.")
        }
        interfaceID = name
        try ensureAuthorized()
        let networks: Set<CWNetwork>
        if command.cached { networks = interface.cachedScanResults() ?? [] }
        else { networks = try interface.scanForNetworks(withName: nil, includeHidden: true) }
        let current = interface.bssid()
        let observations = networks.sorted { $0.rssiValue > $1.rssiValue }.map { network in
            let channel = network.wlanChannel
            return contractObservation(ContractNetwork(
                ssid: network.ssid, ssidData: network.ssidData, bssid: network.bssid,
                rssi: network.rssiValue, noise: network.noiseMeasurement,
                channel: channel?.channelNumber, band: channel.map { bandLabel($0.channelBand) } ?? "unknown",
                width: channel.map { mapWidth($0.channelWidth) }
            ), currentBSSID: current)
        }
        return scanEnvelope(interface: name, started: started, status: command.cached ? "cached" : "completed", observations: observations)
    } catch {
        let failure = error as? BackendFailure ?? BackendFailure(code: "backend_error", message: String(describing: error))
        return scanEnvelope(interface: interfaceID, started: started, status: "failed", error: failure)
    }
}

func contractTable(_ value: [String: Any]) -> String {
    guard let scan = value["scan"] as? [String: Any] else { return "" }
    if let error = scan["error"] as? [String: String] { return "\(error["code"]!): \(error["message"]!)\n" }
    var rows = ["SSID\tBSSID\tRSSI dBm\tMHz\tFRESHNESS"]
    for row in value["observations"] as? [[String: Any]] ?? [] {
        let ssid = (row["ssid"] as? String).map { $0.isEmpty ? "(hidden)" : $0 } ?? "(unavailable)"
        let safe = ssid.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? "?" : String($0) }.joined()
        let rssi = (row["rssi_dbm"] as? Int).map(String.init) ?? "?"
        let frequency = (row["frequency_mhz"] as? Int).map(String.init) ?? "?"
        rows.append("\(safe)\t\(row["bssid"] as? String ?? "?")\t\(rssi)\t\(frequency)\tunknown")
    }
    return rows.joined(separator: "\n") + "\n"
}
