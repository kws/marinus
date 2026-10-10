import Darwin
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}
struct TestSkip: Error {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #fileID, line: UInt = #line) throws {
    if actual != expected {
        throw TestFailure(description: "\(file):\(line): \(message)\nactual: \(actual)\nexpected: \(expected)")
    }
}
func expectTrue(_ actual: Bool, _ message: String = "", file: String = #fileID, line: UInt = #line) throws {
    try expectEqual(actual, true, message, file: file, line: line)
}
func expectFalse(_ actual: Bool, _ message: String = "", file: String = #fileID, line: UInt = #line) throws {
    try expectEqual(actual, false, message, file: file, line: line)
}
func expectNil<T>(_ actual: T?, _ message: String = "", file: String = #fileID, line: UInt = #line) throws {
    if actual != nil { throw TestFailure(description: "\(file):\(line): expected nil. \(message)") }
}
func expectUnwrap<T>(_ actual: T?, file: String = #fileID, line: UInt = #line) throws -> T {
    guard let actual else { throw TestFailure(description: "\(file):\(line): expected a value") }
    return actual
}
func expectThrows<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: String = #fileID, line: UInt = #line) throws {
    do { _ = try expression() }
    catch { return }
    throw TestFailure(description: "\(file):\(line): expected an error. \(message)")
}

@main
struct TestRunner {
    static func main() {
        let cases: [(String, () throws -> Void)] = [
            ("testNativeMappingPreservesNullsBytesAndUnknownFreshness", ContractTests().testNativeMappingPreservesNullsBytesAndUnknownFreshness),
            ("testSharedScanAndFailureEnvelope", ContractTests().testSharedScanAndFailureEnvelope),
            ("testCommonOptionsAndExplicitCompatibilityMode", ContractTests().testCommonOptionsAndExplicitCompatibilityMode),
            ("testDefaultScanUsesSharedContract", CommandTests().testDefaultScanUsesSharedContract),
            ("testDetailedJSONScanAndInfo", CommandTests().testDetailedJSONScanAndInfo),
            ("testPasswordFlagsWorkBeforeOrAfterSSID", CommandTests().testPasswordFlagsWorkBeforeOrAfterSSID),
            ("testDoubleDashAndBooleanFlags", CommandTests().testDoubleDashAndBooleanFlags),
            ("testHelpAndVersionNeedNoApp", CommandTests().testHelpAndVersionNeedNoApp),
            ("testInvalidCommandsAreRejectedBeforeLaunch", CommandTests().testInvalidCommandsAreRejectedBeforeLaunch),
            ("testDurationParsing", CommandTests().testDurationParsing),
            ("testBareExecutableExplainsThatAnAppBundleIsRequired", LauncherTests().testBareExecutableExplainsThatAnAppBundleIsRequired),
            ("testOverrideRejectsTheOldHelperBundle", LauncherTests().testOverrideRejectsTheOldHelperBundle),
            ("testLaunchServicesRoundTripWithThePackagedSwiftExecutable", LauncherTests().testLaunchServicesRoundTripWithThePackagedSwiftExecutable),
            ("testScanJSONPreservesTheExistingFieldNamesAndValues", OutputTests().testScanJSONPreservesTheExistingFieldNamesAndValues),
            ("testTableHasExistingColumnOrderSpacingAndFlags", OutputTests().testTableHasExistingColumnOrderSpacingAndFlags),
            ("testEmptyScanIsAJSONList", OutputTests().testEmptyScanIsAJSONList),
            ("testInfoSelectsCurrentAndPreservesDisconnectedJSON", OutputTests().testInfoSelectsCurrentAndPreservesDisconnectedJSON),
            ("testDetailedModeIsPassedThroughToScanning", OutputTests().testDetailedModeIsPassedThroughToScanning),
            ("testPasswordOutputAndMissingPasswordExitCodes", OutputTests().testPasswordOutputAndMissingPasswordExitCodes),
            ("testErrorsKeepJSONStdoutClean", OutputTests().testErrorsKeepJSONStdoutClean),
            ("testSummaryPreservesStrongestSSIDAndLegacyCurrentFlag", ScannerTests().testSummaryPreservesStrongestSSIDAndLegacyCurrentFlag),
            ("testDetailedScanPreservesEveryAPAndMarksOnlyConnectedBSSID", ScannerTests().testDetailedScanPreservesEveryAPAndMarksOnlyConnectedBSSID),
            ("testMissingCurrentBSSIDDoesNotFallBackToSSIDOrMatchEmptyBSSIDs", ScannerTests().testMissingCurrentBSSIDDoesNotFallBackToSSIDOrMatchEmptyBSSIDs),
            ("testHiddenSSIDIsIncludedOnlyInDetailedMode", ScannerTests().testHiddenSSIDIsIncludedOnlyInDetailedMode),
            ("testSummaryStillMarksConnectedSavedPlaceholder", ScannerTests().testSummaryStillMarksConnectedSavedPlaceholder),
            ("testUnobservedConnectedBSSIDDoesNotMarkAnotherAPCurrent", ScannerTests().testUnobservedConnectedBSSIDDoesNotMarkAnotherAPCurrent),
            ("testDetailedOrderingIsStableForTiedSignals", ScannerTests().testDetailedOrderingIsStableForTiedSignals),
            ("testCoreWLANWidthConstants", ScannerTests().testCoreWLANWidthConstants),
            ("testBSSIDNormalizationRejectsAbsentAndInvalidIdentifiers", ScannerTests().testBSSIDNormalizationRejectsAbsentAndInvalidIdentifiers),
        ]
        var failures = 0
        var skipped = 0
        for (name, test) in cases {
            do { try test(); print("PASS \(name)") }
            catch let skip as TestSkip { skipped += 1; print("SKIP \(name): \(skip.reason)") }
            catch {
                failures += 1
                FileHandle.standardError.write(Data("FAIL \(name): \(error)\n".utf8))
            }
        }
        print("\(cases.count - failures - skipped) passed, \(skipped) skipped, \(failures) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
