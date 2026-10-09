import Foundation

enum CommandKind: String { case scan, watch, interfaces, info, password, help, version }

struct CLICommand: Equatable {
    var kind: CommandKind
    var asJSON = false
    var allBSSIDs = false
    var noPromptHint = false
    var timeout: TimeInterval = 90
    var ssid: String?
    var legacy = false
    var cached = false
    var interfaceID: String?
    var interval: TimeInterval = 5
    var count: Int?
    var output: String?

    var needsApp: Bool { kind == .scan || kind == .watch || kind == .info || kind == .password }
    var scanMode: ScanMode { allBSSIDs ? .bssids : .summary }
}

enum CLIParseError: Error, CustomStringConvertible {
    case usage(String)
    var description: String {
        switch self { case .usage(let message): return message }
    }
}

let usage = """
marinus — Wi-Fi inspection for macOS 13+

Usage:
  marinus <command> [flags] [args]

Commands:
  scan              List nearby Wi-Fi networks.
  interfaces        List Wi-Fi interfaces without scanning.
  watch             Repeat scans; --json emits JSON Lines.
  info              Show the current network.
  password <ssid>   Print a saved Keychain password.
  help              Show this message.
  version           Print version information.

Flags:
  --json            Emit the shared 0.1.0 contract (scan, watch, interfaces).
  --interface <id>  Select a Wi-Fi device, e.g. en0 (scan, watch).
  --cached          Explicitly read cached results (scan).
  --legacy          Original macOS scan format and SSID summary (scan).
  --interval <sec>  Pause after each watch scan; default 5 seconds.
  --count <n>       Stop watch after n scans.
  --output <file>   Save JSON/JSON Lines to a new file (scan, watch).
  --bssids          Legacy scan/info: retain every observed BSSID instead of
                    the strongest result per SSID. Survey scans always retain all BSSIDs.
  --no-prompt-hint  Suppress the Keychain prompt hint (password).
  --timeout <time>  Maximum command duration, e.g. 60s or 2m.
                    Default: 90s for scanning, 60s for passwords.

Examples:
  marinus scan
  marinus scan --json
  marinus watch --count 10 --json
  marinus info --bssids
  marinus password "MyHomeWiFi" --json

"""

func parseDuration(_ text: String) -> TimeInterval? {
    let expression = try! NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)(ms|s|m|h)"#)
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = expression.matches(in: text, range: range)
    var consumed = 0
    var duration: TimeInterval = 0
    for match in matches {
        guard match.range.location == consumed,
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let number = Double(text[numberRange]) else { return nil }
        let multiplier: Double
        switch text[unitRange] {
        case "ms": multiplier = 0.001
        case "s": multiplier = 1
        case "m": multiplier = 60
        case "h": multiplier = 3600
        default: return nil
        }
        duration += number * multiplier
        consumed += match.range.length
    }
    return consumed == range.length && duration > 0 && duration.isFinite ? duration : nil
}

func parseCommand(_ arguments: [String]) throws -> CLICommand {
    guard let first = arguments.first else { throw CLIParseError.usage(usage) }
    if ["--help", "-h"].contains(first) { return CLICommand(kind: .help) }
    if ["--version", "-v"].contains(first) { return CLICommand(kind: .version) }
    guard let kind = CommandKind(rawValue: first) else {
        throw CLIParseError.usage("unknown command \(first)\n\n\(usage)")
    }
    var command = CLICommand(kind: kind, timeout: kind == .password ? 60 : 90)
    var positionals: [String] = []
    var index = 1
    var parseFlags = true
    while index < arguments.count {
        let argument = arguments[index]
        index += 1
        if argument == "--", parseFlags { parseFlags = false; continue }
        if !parseFlags || !argument.hasPrefix("-") {
            positionals.append(argument)
            continue
        }
        if ["--help", "-h"].contains(argument) { return CLICommand(kind: .help) }
        let components = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let flag = String(components[0])
        let value = components.count == 2 ? String(components[1]) : nil
        func booleanValue() throws -> Bool {
            guard let value else { return true }
            switch value {
            case "true": return true
            case "false": return false
            default: throw CLIParseError.usage("invalid value for \(flag): \(value)")
            }
        }
        switch flag {
        case "--json" where command.needsApp || kind == .interfaces:
            command.asJSON = try booleanValue()
        case "--legacy" where kind == .scan:
            command.legacy = try booleanValue()
        case "--cached" where kind == .scan:
            command.cached = try booleanValue()
        case "--interface", "--output", "--interval", "--count":
            guard kind == .scan || kind == .watch else { throw CLIParseError.usage("\(flag) requires scan or watch") }
            let text: String
            if let value { text = value }
            else {
                guard index < arguments.count else { throw CLIParseError.usage("\(flag) requires a value") }
                text = arguments[index]; index += 1
            }
            guard !text.isEmpty else { throw CLIParseError.usage("\(flag) requires a value") }
            switch flag {
            case "--interface": command.interfaceID = text
            case "--output": command.output = text
            case "--interval" where kind == .watch:
                guard let seconds = Double(text), seconds.isFinite, seconds >= 1, seconds <= 86400 else {
                    throw CLIParseError.usage("--interval needs 1..86400 seconds")
                }
                command.interval = seconds
            case "--count" where kind == .watch:
                guard let count = Int(text), count > 0 else { throw CLIParseError.usage("--count needs a positive integer") }
                command.count = count
            default: throw CLIParseError.usage("\(flag) is only supported by watch")
            }
        case "--bssids" where kind == .scan || kind == .info:
            command.allBSSIDs = try booleanValue()
        case "--no-prompt-hint" where kind == .password:
            command.noPromptHint = try booleanValue()
        case "--timeout" where command.needsApp:
            let durationText: String
            if let value { durationText = value }
            else {
                guard index < arguments.count else {
                    throw CLIParseError.usage("--timeout requires a duration")
                }
                durationText = arguments[index]
                index += 1
            }
            guard let duration = parseDuration(durationText) ?? Double(durationText), duration.isFinite, duration > 0 else {
                throw CLIParseError.usage("invalid timeout \(durationText); use a positive duration such as 60s")
            }
            command.timeout = duration
        default:
            throw CLIParseError.usage("unknown flag for \(kind.rawValue): \(argument)")
        }
    }
    if command.legacy && (command.cached || command.interfaceID != nil || command.output != nil) {
        throw CLIParseError.usage("--legacy cannot be combined with --cached, --interface or --output")
    }
    if kind == .password {
        guard positionals.count == 1 else {
            throw CLIParseError.usage("password: expected exactly one SSID argument")
        }
        command.ssid = positionals[0]
    } else if !positionals.isEmpty {
        throw CLIParseError.usage("\(kind.rawValue): unexpected argument \(positionals[0])")
    }
    return command
}
