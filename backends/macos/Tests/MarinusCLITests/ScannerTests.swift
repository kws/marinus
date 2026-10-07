import Foundation
import CoreWLAN

final class ScannerTests {
    private func network(_ bssid: String, rssi: Int, channel: Int, ssid: String = "Home") -> WiFiNetwork {
        WiFiNetwork(
            ssid: ssid, bssid: bssid, rssi: rssi, noise: -95, channel: channel,
            channelBand: channel <= 14 ? "2.4GHz" : "5GHz",
            channelWidth: channel <= 14 ? 20 : 80, security: "WPA2"
        )
    }

    private var accessPoints: [WiFiNetwork] {
        [
            network("aa:bb:cc:dd:ee:01", rssi: -37, channel: 1),
            network("aa:bb:cc:dd:ee:02", rssi: -43, channel: 36),
            network("aa:bb:cc:dd:ee:03", rssi: -55, channel: 6),
            network("aa:bb:cc:dd:ee:04", rssi: -59, channel: 100),
        ]
    }

    func testSummaryPreservesStrongestSSIDAndLegacyCurrentFlag() throws {
        let result = selectNetworks(
            accessPoints, savedSSIDs: ["Home", "Away"], currentSSID: "Home",
            currentBSSID: "aa:bb:cc:dd:ee:02", mode: .summary
        )
        try expectEqual(result.count, 2)
        try expectEqual(result[0].bssid, "aa:bb:cc:dd:ee:01")
        try expectEqual(result[0].channel, 1)
        try expectTrue(result[0].current)
        try expectTrue(result[0].saved)
        try expectEqual(result[1], WiFiNetwork.savedPlaceholder(ssid: "Away"))
    }

    func testDetailedScanPreservesEveryAPAndMarksOnlyConnectedBSSID() throws {
        let result = selectNetworks(
            accessPoints, savedSSIDs: ["Home", "Away"], currentSSID: "Home",
            currentBSSID: "AA:BB:CC:DD:EE:02", mode: .bssids
        )
        try expectEqual(result.count, 4)
        try expectEqual(Set(result.map(\.channel)), [1, 36, 6, 100])
        try expectEqual(result.filter(\.current).map(\.bssid), ["aa:bb:cc:dd:ee:02"])
        try expectTrue(result.allSatisfy(\.saved))
        try expectFalse(result.contains(where: { $0.ssid == "Away" }))
    }

    func testMissingCurrentBSSIDDoesNotFallBackToSSIDOrMatchEmptyBSSIDs() throws {
        let observed = accessPoints + [
            network("", rssi: -60, channel: 11), network("", rssi: -70, channel: 48),
        ]
        for current in [nil, "", "invalid"] as [String?] {
            let result = selectNetworks(
                observed, savedSSIDs: [], currentSSID: "Home", currentBSSID: current, mode: .bssids
            )
            try expectEqual(result.count, 6)
            try expectTrue(result.allSatisfy { !$0.current })
        }
    }

    func testHiddenSSIDIsIncludedOnlyInDetailedMode() throws {
        let observed = [network("aa:bb:cc:dd:ee:05", rssi: -30, channel: 11, ssid: "")]
        try expectTrue(selectNetworks(
            observed, savedSSIDs: [], currentSSID: nil, currentBSSID: nil, mode: .summary
        ).isEmpty)
        let detailed = selectNetworks(
            observed, savedSSIDs: [], currentSSID: nil, currentBSSID: "aa:bb:cc:dd:ee:05", mode: .bssids
        )
        try expectEqual(detailed.count, 1)
        try expectTrue(detailed[0].current)
        try expectTrue(networkTable(detailed).contains("<hidden>"))
    }

    func testSummaryStillMarksConnectedSavedPlaceholder() throws {
        let result = selectNetworks(
            [], savedSSIDs: ["Home"], currentSSID: "Home",
            currentBSSID: "aa:bb:cc:dd:ee:02", mode: .summary
        )
        try expectEqual(result.count, 1)
        try expectEqual(result[0].rssi, 0)
        try expectTrue(result[0].current)
        try expectTrue(result[0].saved)
    }

    func testUnobservedConnectedBSSIDDoesNotMarkAnotherAPCurrent() throws {
        let result = selectNetworks(
            accessPoints, savedSSIDs: [], currentSSID: "Home",
            currentBSSID: "aa:bb:cc:dd:ee:99", mode: .bssids
        )
        try expectTrue(result.allSatisfy { !$0.current })
    }

    func testDetailedOrderingIsStableForTiedSignals() throws {
        let observed = [
            network("aa:bb:cc:dd:ee:02", rssi: -43, channel: 36),
            network("aa:bb:cc:dd:ee:01", rssi: -43, channel: 1),
        ]
        let first = selectNetworks(observed, savedSSIDs: [], currentSSID: nil, currentBSSID: nil, mode: .bssids)
        let second = selectNetworks(Array(observed.reversed()), savedSSIDs: [], currentSSID: nil, currentBSSID: nil, mode: .bssids)
        try expectEqual(first, second)
    }

    func testCoreWLANWidthConstants() throws {
        let cases: [(CWChannelWidth, Int)] = [
            (.widthUnknown, 0), (.width20MHz, 20), (.width40MHz, 40),
            (.width80MHz, 80), (.width160MHz, 160),
        ]
        for (width, expected) in cases { try expectEqual(mapWidth(width), expected) }
    }

    func testBSSIDNormalizationRejectsAbsentAndInvalidIdentifiers() throws {
        try expectEqual(normalizedBSSID("AA:bb:CC:dd:EE:ff"), "aa:bb:cc:dd:ee:ff")
        for invalid in [nil, "", "a:b:c:d:e:f", "aa:bb:cc:dd:ee", "aa:bb:cc:dd:ee:gg"] as [String?] {
            try expectEqual(normalizedBSSID(invalid), "")
        }
    }
}
