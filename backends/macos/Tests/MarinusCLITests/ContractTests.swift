import Foundation

final class ContractTests {
    func testNativeMappingPreservesNullsBytesAndUnknownFreshness() throws {
        let network = ContractNetwork(ssid: nil, ssidData: Data([255, 65]), bssid: "02:00:00:00:00:01",
            rssi: -55, noise: 0, channel: 36, band: "5GHz", width: 0)
        let row = contractObservation(network, currentBSSID: nil)
        try expectTrue(row["ssid"] is NSNull)
        try expectEqual(row["ssid_bytes_base64"] as? String, "/0E=")
        try expectEqual(row["rssi_dbm"] as? Int, -55)
        for field in ["noise_dbm", "strength_percent", "channel_width_mhz", "connected", "last_seen_age_ms"] {
            try expectTrue(row[field] is NSNull, field)
        }
        try expectEqual(row["freshness"] as? String, "unknown")
        try expectEqual(row["frequency_mhz"] as? Int, 5180)
        try expectEqual(channelFrequency(number: 14, band: "2.4GHz"), 2484)
        try expectEqual(channelFrequency(number: 2, band: "6GHz"), 5935)
        try expectNil(channelFrequency(number: 1, band: "unknown"))
    }

    func testSharedScanAndFailureEnvelope() throws {
        let raw = [
            ContractNetwork(ssid: "Example", ssidData: Data("Example".utf8), bssid: "02:00:00:00:00:01", rssi: -55, noise: -95, channel: 1, band: "2.4GHz", width: 20),
            ContractNetwork(ssid: "Example", ssidData: Data("Example".utf8), bssid: "02:00:00:00:00:02", rssi: -70, noise: -95, channel: 36, band: "5GHz", width: 80),
            ContractNetwork(ssid: "", ssidData: Data(), bssid: nil, rssi: 0, noise: 0, channel: nil, band: "unknown", width: nil),
        ]
        let rows = raw.map { contractObservation($0, currentBSSID: "02:00:00:00:00:02") }
        let completed = scanEnvelope(interface: "synthetic0", started: contractTimestamp(), status: "completed", observations: rows)
        let result = executeCommand(CLICommand(kind: .scan, asJSON: true), version: "test", surveyScan: { _ in completed })
        let value = try expectUnwrap(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        try expectEqual(value["contract_version"] as? String, "0.1.0")
        try expectEqual((value["observations"] as? [[String: Any]])?.count, 3)
        let failure = scanEnvelope(interface: "synthetic0", started: contractTimestamp(), status: "failed", observations: rows,
            error: BackendFailure(code: "permission_denied", message: "Synthetic permission denial"))
        let denied = executeCommand(CLICommand(kind: .scan, asJSON: true), version: "test", surveyScan: { _ in failure })
        try expectEqual(denied.exitCode, 1)
        try expectEqual((failure["observations"] as? [[String: Any]])?.count, 0)
        if let directory = ProcessInfo.processInfo.environment["MARINUS_FIXTURE_DIR"] {
            let url = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for (name, fixture) in [("macos-generated-completed", completed), ("macos-generated-denied", failure),
                ("macos-generated-cached", scanEnvelope(interface: "synthetic0", started: contractTimestamp(), status: "cached", observations: rows))] {
                try contractJSON(fixture).write(to: url.appendingPathComponent(name + ".json"), atomically: true, encoding: .utf8)
            }
        }
    }

    func testCommonOptionsAndExplicitCompatibilityMode() throws {
        let scan = try parseCommand(["scan", "--interface", "en1", "--cached", "--timeout", "15", "--json"])
        try expectEqual(scan.interfaceID, "en1")
        try expectTrue(scan.cached)
        try expectFalse(scan.legacy)
        let watch = try parseCommand(["watch", "--count", "2", "--interval", "3", "--output", "capture.jsonl"])
        try expectEqual(watch.count, 2)
        try expectEqual(watch.interval, 3)
        try expectTrue(try parseCommand(["scan", "--legacy"]).legacy)
        try expectFalse(try parseCommand(["interfaces", "--json"]).needsApp)
        for args in [["watch", "--cached"], ["scan", "--legacy", "--cached"], ["info", "--interface", "en1"], ["watch", "--count", "0"]] {
            try expectThrows(try parseCommand(args))
        }
    }
}
