import Foundation

final class CommandTests {
    func testDefaultScanUsesSharedContract() throws {
        let command = try parseCommand(["scan"])
        try expectEqual(command, CLICommand(kind: .scan))
        try expectFalse(command.legacy)
    }

    func testDetailedJSONScanAndInfo() throws {
        for kind in ["scan", "info"] {
            let command = try parseCommand([kind, "--bssids", "--json"])
            try expectEqual(command.scanMode, .bssids)
            try expectTrue(command.asJSON)
        }
    }

    func testPasswordFlagsWorkBeforeOrAfterSSID() throws {
        let before = try parseCommand(["password", "--json", "--timeout", "1m30s", "--no-prompt-hint", "Home WiFi"])
        let after = try parseCommand(["password", "Home WiFi", "--json", "--timeout=1m30s", "--no-prompt-hint"])
        try expectEqual(before, after)
        try expectEqual(after.ssid, "Home WiFi")
        try expectEqual(after.timeout, 90)
        try expectTrue(after.noPromptHint)
    }

    func testDoubleDashAndBooleanFlags() throws {
        let password = try parseCommand(["password", "--json", "--", "-SSID"])
        try expectEqual(password.ssid, "-SSID")
        let scan = try parseCommand(["scan", "--json=false", "--bssids=false"])
        try expectFalse(scan.asJSON)
        try expectFalse(scan.allBSSIDs)
    }

    func testHelpAndVersionNeedNoApp() throws {
        for arguments in [["help"], ["--help"], ["scan", "--help"], ["password", "-h"], ["version"], ["--version"], ["-v"]] {
            try expectFalse(try parseCommand(arguments).needsApp)
        }
    }

    func testInvalidCommandsAreRejectedBeforeLaunch() throws {
        for arguments in [
            [], ["unknown"], ["scan", "extra"], ["info", "--no-prompt-hint"],
            ["scan", "--json=maybe"], ["password"], ["password", "one", "two"],
            ["password", "Home", "--bssids"], ["scan", "--timeout"],
            ["scan", "--timeout=0s"], ["scan", "--timeout=-1s"], ["scan", "--timeout=nan"],
        ] {
            try expectThrows(try parseCommand(arguments), "\(arguments)")
        }
    }

    func testDurationParsing() throws {
        try expectEqual(parseDuration("1m30s"), 90)
        try expectEqual(parseDuration("1.5s"), 1.5)
        try expectEqual(parseDuration("500ms"), 0.5)
        try expectEqual(parseDuration("2h"), 7200)
        for invalid in ["", "0s", "-1s", "nan", "10", "s", "1ss", "x1s", "1s x", "1s2"] {
            try expectNil(parseDuration(invalid), invalid)
        }
    }
}
