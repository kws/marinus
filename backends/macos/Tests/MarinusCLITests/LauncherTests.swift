import Foundation

final class LauncherTests {
    func testBareExecutableExplainsThatAnAppBundleIsRequired() throws {
        try expectThrows(try appBundleURL(executablePath: "/tmp/bare-marinus", override: nil))
    }

    func testOverrideRejectsTheOldHelperBundle() throws {
        try expectThrows(try appBundleURL(override: "/tmp/old-WifiScanner.app"))
    }

    func testLaunchServicesRoundTripWithThePackagedSwiftExecutable() throws {
        guard let path = ProcessInfo.processInfo.environment["MARINUS_TEST_APP"] else {
            throw TestSkip("Build the app and set MARINUS_TEST_APP to test the LaunchServices round trip.")
        }
        let bundle = URL(fileURLWithPath: path)
        let result = try launchInApp(arguments: ["version"], timeout: 15, bundleURL: bundle)
        try expectEqual(result.exitCode, 0)
        try expectEqual(result.stdout, "marinus 0.1.0\n")
        try expectTrue(result.stderr.isEmpty)
        let invalid = try launchInApp(arguments: ["invalid-command"], timeout: 15, bundleURL: bundle)
        try expectEqual(invalid.exitCode, 2)
        try expectTrue(invalid.stdout.isEmpty)
        try expectTrue(invalid.stderr.contains("unknown command"))
    }
}
