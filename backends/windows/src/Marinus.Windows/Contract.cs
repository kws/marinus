using System.Globalization;
using System.Text.Json;

namespace Marinus.Windows;

public sealed record BackendInfo(string Platform = "windows", string Name = "native-wlan", string BackendVersion = "0.1.0");
public sealed record ScanInterface(string Id, string? Driver = null);
public sealed record ScanCapabilities(bool RssiDbm = true, bool StrengthPercent = true,
    bool NoiseDbm = false, bool ChannelWidthMhz = false, int? LastSeenResolutionMs = null);
public sealed record ScanError(string Code, string Message);
public sealed record ScanInfo(string Status, string StartedAt, string? CompletedAt, ScanError? Error);
public sealed record Observation(string? Ssid, string? SsidBytesBase64, string? Bssid,
    int? RssiDbm, int? StrengthPercent, int? NoiseDbm, int? FrequencyMhz, int? ChannelWidthMhz,
    bool? Connected, string Freshness, long? LastSeenAgeMs);
public sealed record ScanResult(string ContractVersion, BackendInfo Backend, ScanInterface Interface,
    ScanCapabilities Capabilities, ScanInfo Scan, IReadOnlyList<Observation> Observations);

public static class ContractJson
{
    public static string Serialize<T>(T value, bool indented = false) =>
        JsonSerializer.Serialize(value, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            WriteIndented = indented
        });

    internal static string Timestamp(DateTimeOffset value) =>
        value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);
}
