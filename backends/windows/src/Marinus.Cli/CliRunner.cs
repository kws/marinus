using System.Globalization;
using System.Text;
using Marinus.Windows;

namespace Marinus.Cli;

public static class CliRunner
{
    private const string Help = """
        Marinus — Windows Wi-Fi measurements

        marinus interfaces [--json]
        marinus scan [--interface GUID] [--cached] [--timeout SECONDS] [--json] [--output FILE]
        marinus watch [--interface GUID] [--timeout SECONDS] [--interval SECONDS] [--count N]
                      [--json] [--output FILE]

        scan requests a new scan; --cached explicitly reads the existing cache.
        watch requests repeated scans, waiting 5 seconds between scans by default.
        --json writes the draft 0.1.0 contract; watch uses one compact JSON object per line.
        --output saves JSON (scan) or JSON Lines (watch) to a new file; existing files are preserved.
        Scan timeout defaults to 15 seconds. Ctrl+C stops watch. No administrator access is required;
        grant location access when Windows asks. Use --interface when several adapters are present.
        """;

    public static async Task<int> RunAsync(string[] args, IWindowsScanner scanner, TextWriter output,
        TextWriter error, CancellationToken cancellationToken = default)
    {
        try
        {
            var command = Command.Parse(args);
            if (command.Name == "help") { output.WriteLine(Help); return 0; }
            if (command.Name == "interfaces")
            {
                var interfaces = scanner.GetInterfaces();
                if (command.Json) output.WriteLine(ContractJson.Serialize(interfaces, true));
                else
                {
                    output.WriteLine("INTERFACE GUID                         STATE           ADAPTER");
                    foreach (var item in interfaces)
                        output.WriteLine($"{item.Id:D}   {item.State,-15} {SafeText(item.Description)}");
                    if (interfaces.Count == 0) output.WriteLine("No enabled Wi-Fi adapters found.");
                }
                return 0;
            }

            using StreamWriter? file = command.Output is null ? null : CreateOutput(command.Output);
            var options = new ScanOptions(command.InterfaceId, command.Cached, command.Timeout);
            for (int index = 0; command.Count is null || index < command.Count; index++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var result = await scanner.ScanAsync(options, cancellationToken);
                bool indented = command.Name == "scan";
                string json = ContractJson.Serialize(result, indented);
                if (file is not null) { file.WriteLine(json); file.Flush(); }
                if (command.Json) output.WriteLine(json);
                else WriteTable(result, output);
                output.Flush();
                if (result.Scan.Status == "failed")
                {
                    if (command.Json) error.WriteLine($"{result.Scan.Error!.Code}: {result.Scan.Error.Message}");
                    return 1;
                }
                // Keep watch attached to its first adapter even if available interfaces later change.
                options = options with { InterfaceId = Guid.Parse(result.Interface.Id) };
                if (command.Name == "scan" || (command.Count is { } count && index + 1 >= count)) break;
                await Task.Delay(command.Interval, cancellationToken);
            }
            return 0;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { return 130; }
        catch (ArgumentException exception) { error.WriteLine(exception.Message); error.WriteLine("Use 'marinus help' for commands."); return 2; }
        catch (Exception exception) when (exception is WlanException or PlatformNotSupportedException or IOException or UnauthorizedAccessException)
        {
            error.WriteLine(exception.Message);
            return 1;
        }
    }

    private static StreamWriter CreateOutput(string path)
    {
        string fullPath = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        return new StreamWriter(new FileStream(fullPath, FileMode.CreateNew, FileAccess.Write, FileShare.Read), new UTF8Encoding(false));
    }

    private static void WriteTable(ScanResult result, TextWriter output)
    {
        output.WriteLine($"{result.Scan.CompletedAt ?? result.Scan.StartedAt}  {result.Scan.Status}  {result.Interface.Id}");
        if (result.Scan.Error is { } error) { output.WriteLine($"{error.Code}: {error.Message}"); return; }
        output.WriteLine("SSID                              BSSID              RSSI     QUALITY  MHz   LINK  FRESHNESS");
        foreach (var item in result.Observations)
        {
            string ssid = item.Ssid switch { null => "(unavailable)", "" => "(hidden)", _ => SafeText(item.Ssid) };
            string link = item.Connected switch { true => "yes", false => "no", _ => "?" };
            output.WriteLine($"{ssid,-32}  {item.Bssid ?? "?",-17}  {Value(item.RssiDbm),5} dBm  {Value(item.StrengthPercent),3}%  {Value(item.FrequencyMhz),4}  {link,-4}  {item.Freshness}");
        }
        output.WriteLine($"{result.Observations.Count} BSS observations");
    }

    private static string Value(int? value) => value?.ToString(CultureInfo.InvariantCulture) ?? "?";

    internal static string SafeText(string value) => string.Concat(value.Select(character =>
        char.IsControl(character) || character is '\u2028' or '\u2029' or '\u202a' or '\u202b' or '\u202c' or '\u202d' or '\u202e' or '\u2066' or '\u2067' or '\u2068' or '\u2069'
            ? $"\\u{(int)character:x4}" : character.ToString()));
}

internal sealed record Command(string Name, Guid? InterfaceId, bool Cached, bool Json,
    TimeSpan Timeout, TimeSpan Interval, int? Count, string? Output)
{
    internal static Command Parse(string[] args)
    {
        if (args.Length == 0 || (args.Length == 1 && args[0] is "help" or "--help" or "-h"))
            return new Command("help", null, false, false, TimeSpan.FromSeconds(15), TimeSpan.FromSeconds(5), 1, null);
        string name = args[0];
        if (name is not ("interfaces" or "scan" or "watch")) throw new ArgumentException($"Unknown command '{name}'.");
        Guid? interfaceId = null;
        bool cached = false, json = false;
        TimeSpan timeout = TimeSpan.FromSeconds(15), interval = TimeSpan.FromSeconds(5);
        int? count = name == "scan" ? 1 : null;
        string? output = null;
        var seen = new HashSet<string>();
        for (int index = 1; index < args.Length; index++)
        {
            string option = args[index];
            if (!seen.Add(option)) throw new ArgumentException($"Duplicate option '{option}'.");
            string Value()
            {
                if (++index >= args.Length || args[index].StartsWith("--", StringComparison.Ordinal))
                    throw new ArgumentException($"{option} needs a value.");
                return args[index];
            }
            if (name == "interfaces" && option != "--json") throw new ArgumentException($"{option} is not supported by interfaces.");
            switch (option)
            {
                case "--json": json = true; break;
                case "--cached" when name == "scan": cached = true; break;
                case "--interface":
                    if (!Guid.TryParse(Value(), out var id)) throw new ArgumentException("--interface needs a valid interface GUID.");
                    interfaceId = id;
                    break;
                case "--timeout": timeout = Seconds(Value(), option, 0.1, 300); break;
                case "--interval" when name == "watch": interval = Seconds(Value(), option, 1, 86400); break;
                case "--count" when name == "watch":
                    if (!int.TryParse(Value(), NumberStyles.None, CultureInfo.InvariantCulture, out var amount) || amount < 1)
                        throw new ArgumentException("--count needs a positive integer.");
                    count = amount;
                    break;
                case "--output":
                    output = Value();
                    if (string.IsNullOrWhiteSpace(output)) throw new ArgumentException("--output needs a file path.");
                    break;
                default: throw new ArgumentException($"Unknown option '{option}' for {name}.");
            }
        }
        return new Command(name, interfaceId, cached, json, timeout, interval, count, output);
    }

    private static TimeSpan Seconds(string value, string option, double minimum, double maximum)
    {
        if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds)
            || !double.IsFinite(seconds) || seconds < minimum || seconds > maximum)
            throw new ArgumentException($"{option} needs a number between {minimum} and {maximum} seconds.");
        return TimeSpan.FromSeconds(seconds);
    }
}
