import CoreLocation
import CoreWLAN
import Foundation
import Security

enum WiFiError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let message): return message }
    }
}

enum ScanMode { case summary, bssids }

struct WiFiNetwork: Codable, Equatable {
    var ssid: String
    var bssid: String
    var rssi: Int
    var noise: Int
    var channel: Int
    var channelBand: String
    var channelWidth: Int
    var security: String
    var phyMode = ""
    var current = false
    var saved = false

    enum CodingKeys: String, CodingKey {
        case ssid, bssid, rssi, noise, channel, security, current, saved
        case channelBand = "channel_band"
        case channelWidth = "channel_width"
        case phyMode = "phy_mode"
    }

    static func savedPlaceholder(ssid: String) -> WiFiNetwork {
        WiFiNetwork(
            ssid: ssid, bssid: "", rssi: 0, noise: 0, channel: 0,
            channelBand: "unknown", channelWidth: 0, security: "unknown", saved: true
        )
    }
}

func normalizedBSSID(_ value: String?) -> String {
    guard let value else { return "" }
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 6 else { return "" }
    var octets: [String] = []
    for part in parts {
        guard part.count == 2, let octet = UInt8(part, radix: 16) else { return "" }
        octets.append(String(format: "%02x", octet))
    }
    return octets.joined(separator: ":")
}

func mapWidth(_ width: CWChannelWidth) -> Int {
    switch width {
    case .widthUnknown: return 0
    case .width20MHz: return 20
    case .width40MHz: return 40
    case .width80MHz: return 80
    case .width160MHz: return 160
    @unknown default: return 0
    }
}

func bandLabel(_ band: CWChannelBand) -> String {
    switch band.rawValue {
    case 1: return "2.4GHz"
    case 2: return "5GHz"
    case 3: return "6GHz"
    default: return "unknown"
    }
}

func securityLabel(_ network: CWNetwork) -> String {
    let probes: [(CWSecurity, String)] = [
        (.wpa3Enterprise, "WPA3-Enterprise"), (.wpa3Personal, "WPA3"),
        (.wpa3Transition, "WPA3"), (.wpa2Enterprise, "WPA2-Enterprise"),
        (.wpa2Personal, "WPA2"), (.personal, "WPA2"),
        (.wpaEnterprise, "WPA2-Enterprise"), (.wpaEnterpriseMixed, "WPA2-Enterprise"),
        (.wpaPersonal, "WPA"), (.wpaPersonalMixed, "WPA"),
        (.enterprise, "WPA2-Enterprise"), (.dynamicWEP, "WEP"),
        (.WEP, "WEP"), (.none, "none"),
    ]
    return probes.first(where: { network.supportsSecurity($0.0) })?.1 ?? "unknown"
}

// Selection stays separate from CoreWLAN so both modes can be tested with
// multiple APs, hidden networks and missing BSSIDs without a live radio.
func selectNetworks(
    _ observed: [WiFiNetwork],
    savedSSIDs: Set<String>,
    currentSSID: String?,
    currentBSSID: String?,
    mode: ScanMode
) -> [WiFiNetwork] {
    var result: [WiFiNetwork]
    switch mode {
    case .summary:
        var bySSID: [String: WiFiNetwork] = [:]
        for network in observed where !network.ssid.isEmpty {
            if let previous = bySSID[network.ssid], previous.rssi >= network.rssi { continue }
            bySSID[network.ssid] = network
        }
        result = bySSID.values.map { network in
            var network = network
            network.current = currentSSID == network.ssid
            network.saved = savedSSIDs.contains(network.ssid)
            return network
        }
        for ssid in savedSSIDs where bySSID[ssid] == nil {
            var placeholder = WiFiNetwork.savedPlaceholder(ssid: ssid)
            placeholder.current = currentSSID == ssid
            result.append(placeholder)
        }
    case .bssids:
        let connected = normalizedBSSID(currentBSSID)
        result = observed.map { network in
            var network = network
            network.bssid = normalizedBSSID(network.bssid)
            network.current = !connected.isEmpty && network.bssid == connected
            network.saved = savedSSIDs.contains(network.ssid)
            return network
        }
    }
    result.sort { lhs, rhs in
        let leftRSSI = lhs.rssi == 0 ? -999 : lhs.rssi
        let rightRSSI = rhs.rssi == 0 ? -999 : rhs.rssi
        if leftRSSI != rightRSSI { return leftRSSI > rightRSSI }
        // The legacy mode keeps its RSSI-only ordering. Detailed scans use a
        // stable order when signals are tied to make survey snapshots useful.
        if mode == .summary { return false }
        if lhs.ssid != rhs.ssid { return lhs.ssid < rhs.ssid }
        if lhs.bssid != rhs.bssid { return lhs.bssid < rhs.bssid }
        if lhs.channelBand != rhs.channelBand { return lhs.channelBand < rhs.channelBand }
        return lhs.channel < rhs.channel
    }
    return result
}

final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}

func ensureAuthorized() throws {
    let manager = CLLocationManager()
    let delegate = LocationDelegate()
    manager.delegate = delegate
    if manager.authorizationStatus == .notDetermined {
        manager.requestWhenInUseAuthorization()
        let deadline = Date().addingTimeInterval(60)
        while manager.authorizationStatus == .notDetermined, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse: return
    case .denied, .restricted:
        throw BackendFailure(code: "permission_denied", message: "Location Services denied. Enable access for Marinus in System Settings.")
    case .notDetermined:
        throw BackendFailure(code: "scan_timeout", message: "Location Services authorization timed out.")
    @unknown default:
        throw WiFiError.message("Unexpected Location Services authorization status.")
    }
}

func preferredNetworkSSIDs() -> Set<String> {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    process.arguments = ["-listpreferredwirelessnetworks", "en0"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return [] }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    return Set(text.split(separator: "\n").compactMap { line in
        line.hasPrefix("\t") ? String(line.dropFirst()) : nil
    })
}

func scanNetworks(mode: ScanMode) throws -> [WiFiNetwork] {
    try ensureAuthorized()
    guard let interface = CWWiFiClient.shared().interface() else {
        throw WiFiError.message("no Wi-Fi interface available")
    }
    let scanned: Set<CWNetwork>
    do {
        if mode == .bssids {
            scanned = try interface.scanForNetworks(withName: nil, includeHidden: true)
        } else {
            scanned = try interface.scanForNetworks(withName: nil)
        }
    } catch {
        throw WiFiError.message("scan failed: \(error.localizedDescription)")
    }
    let observed = scanned.map { network in
        let channel = network.wlanChannel
        return WiFiNetwork(
            ssid: network.ssid ?? "", bssid: normalizedBSSID(network.bssid),
            rssi: Int(Int16(clamping: network.rssiValue)),
            noise: Int(Int16(clamping: network.noiseMeasurement)),
            channel: Int(UInt16(clamping: channel?.channelNumber ?? 0)),
            channelBand: channel.map { bandLabel($0.channelBand) } ?? "unknown",
            channelWidth: channel.map { mapWidth($0.channelWidth) } ?? 0,
            security: securityLabel(network)
        )
    }
    return selectNetworks(
        observed, savedSSIDs: preferredNetworkSSIDs(),
        currentSSID: interface.ssid(), currentBSSID: interface.bssid(), mode: mode
    )
}

func keychainPassword(ssid: String) throws -> String {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrDescription as String: "AirPort network password",
        kSecAttrAccount as String: ssid,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
        guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw WiFiError.message("keychain returned non-UTF-8 data")
        }
        return password
    case errSecItemNotFound: return ""
    case errSecUserCanceled: throw WiFiError.message("user declined Keychain access")
    default: throw WiFiError.message("SecItemCopyMatching status \(status)")
    }
}
