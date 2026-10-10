import Foundation

final class OutputTests {
    private var network: WiFiNetwork {
        WiFiNetwork(
            ssid: "Home", bssid: "aa:bb:cc:dd:ee:01", rssi: -37, noise: -95,
            channel: 1, channelBand: "2.4GHz", channelWidth: 20,
            security: "WPA2", current: true, saved: true
        )
    }

    private func object(_ text: String) throws -> [String: Any] {
        try expectUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func testScanJSONPreservesTheExistingFieldNamesAndValues() throws {
        let result = executeCommand(CLICommand(kind: .scan, asJSON: true, legacy: true), version: "test", scan: { _ in [self.network] })
        let rows = try expectUnwrap(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [[String: Any]])
        try expectEqual(rows.count, 1)
        try expectEqual(Set(rows[0].keys), [
            "ssid", "bssid", "rssi", "noise", "channel", "channel_band",
            "channel_width", "security", "phy_mode", "current", "saved",
        ])
        try expectEqual(rows[0]["ssid"] as? String, "Home")
        try expectEqual(rows[0]["channel_width"] as? Int, 20)
        try expectEqual(rows[0]["current"] as? Bool, true)
        try expectNil(rows[0]["password"])
        try expectTrue(result.stderr.isEmpty)
        try expectEqual(result.exitCode, 0)
    }

    func testTableHasExistingColumnOrderSpacingAndFlags() throws {
        try expectEqual(networkTable([network]),
            "SSID  BSSID              RSSI  CH  BAND    WIDTH  SEC   FLAGS\n" +
            "Home  aa:bb:cc:dd:ee:01  -37   1   2.4GHz  20     WPA2  CS\n")
    }

    func testEmptyScanIsAJSONList() throws {
        let result = executeCommand(CLICommand(kind: .scan, asJSON: true, legacy: true), version: "test", scan: { _ in [] })
        try expectEqual(result.stdout, "[]\n")
    }

    func testInfoSelectsCurrentAndPreservesDisconnectedJSON() throws {
        var other = network
        other.current = false
        let command = CLICommand(kind: .info, asJSON: true)
        let connected = executeCommand(command, version: "test", scan: { _ in [other, self.network] })
        try expectEqual(try object(connected.stdout)["bssid"] as? String, network.bssid)
        let disconnected = executeCommand(command, version: "test", scan: { _ in [other] })
        try expectEqual(try object(disconnected.stdout)["connected"] as? Bool, false)
        let text = executeCommand(CLICommand(kind: .info), version: "test", scan: { _ in [] })
        try expectEqual(text.stdout, "not connected to a Wi-Fi network\n")
    }

    func testDetailedModeIsPassedThroughToScanning() throws {
        let result = executeCommand(CLICommand(kind: .scan, allBSSIDs: true, legacy: true), version: "test", scan: { mode in
            try expectEqual(mode, .bssids)
            return []
        })
        try expectEqual(result.exitCode, 0)
    }

    func testPasswordOutputAndMissingPasswordExitCodes() throws {
        let text = CLICommand(kind: .password, ssid: "Home")
        let found = executeCommand(text, version: "test", password: { _ in "synthetic-test-value" })
        try expectEqual(found.stdout, "synthetic-test-value\n")
        let missing = executeCommand(text, version: "test", password: { _ in "" })
        try expectEqual(missing.exitCode, 2)
        try expectTrue(missing.stdout.isEmpty)
        var json = text
        json.asJSON = true
        let absentJSON = executeCommand(json, version: "test", password: { _ in "" })
        let absentObject = try object(absentJSON.stdout)
        try expectEqual(absentJSON.exitCode, 0)
        try expectEqual(absentObject["found"] as? Bool, false)
        try expectNil(absentObject["password"])
        let foundJSON = executeCommand(json, version: "test", password: { _ in "synthetic-test-value" })
        try expectEqual(try object(foundJSON.stdout)["password"] as? String, "synthetic-test-value")
    }

    func testErrorsKeepJSONStdoutClean() throws {
        let result = executeCommand(CLICommand(kind: .scan, asJSON: true, legacy: true), version: "test", scan: { _ in
            throw WiFiError.message("synthetic denied")
        })
        try expectEqual(result.exitCode, 1)
        try expectTrue(result.stdout.isEmpty)
        try expectEqual(result.stderr, "error: scan: synthetic denied\n")
    }
}
