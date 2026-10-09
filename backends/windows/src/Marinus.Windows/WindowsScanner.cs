using System.Text;

namespace Marinus.Windows;

public sealed record WirelessInterface(Guid Id, string Description, string State);
public sealed record ScanOptions(Guid? InterfaceId = null, bool Cached = false, TimeSpan? Timeout = null);

public interface IWindowsScanner
{
    IReadOnlyList<WirelessInterface> GetInterfaces();
    Task<ScanResult> ScanAsync(ScanOptions? options = null, CancellationToken cancellationToken = default);
}

/// <summary>One draft-contract result per Wi-Fi interface. This scanner does not change connections.</summary>
public sealed class WindowsScanner : IWindowsScanner
{
    private readonly Func<IWlanClient> _factory;
    private readonly TimeProvider _clock;

    public WindowsScanner() : this(() => new NativeWlanClient(), TimeProvider.System) { }

    internal WindowsScanner(Func<IWlanClient> factory, TimeProvider? clock = null)
    {
        _factory = factory;
        _clock = clock ?? TimeProvider.System;
    }

    public IReadOnlyList<WirelessInterface> GetInterfaces()
    {
        using var client = _factory();
        return client.GetInterfaces();
    }

    public async Task<ScanResult> ScanAsync(ScanOptions? options = null, CancellationToken cancellationToken = default)
    {
        options ??= new ScanOptions();
        var timeout = options.Timeout ?? TimeSpan.FromSeconds(15);
        if (timeout <= TimeSpan.Zero || timeout > TimeSpan.FromMinutes(5))
            throw new ArgumentOutOfRangeException(nameof(options), "Scan timeout must be greater than zero and at most five minutes.");

        cancellationToken.ThrowIfCancellationRequested();
        var started = _clock.GetUtcNow();
        string interfaceId = options.InterfaceId?.ToString("D") ?? "auto";
        try
        {
            using var client = _factory();
            var interfaces = client.GetInterfaces();
            WirelessInterface? selected;
            if (options.InterfaceId is { } requested)
                selected = interfaces.SingleOrDefault(item => item.Id == requested);
            else if (interfaces.Count > 1)
                return Failed("interface_unavailable", "Multiple Wi-Fi interfaces are available; select an interface GUID.");
            else
                selected = interfaces.SingleOrDefault();

            if (selected is null)
                return Failed("interface_unavailable", "The requested Wi-Fi interface is unavailable, or no Wi-Fi adapter is enabled.");
            interfaceId = selected.Id.ToString("D");

            DateTimeOffset? requestedAt = null;
            if (!options.Cached)
                requestedAt = await client.RequestScanAsync(selected.Id, timeout, cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            var entries = client.ReadBss(selected.Id);
            var connectedBssid = client.ReadConnectedBssid(selected.Id);
            var completed = _clock.GetUtcNow();
            var observations = entries.Select(entry => Normalize(entry, connectedBssid, completed, requestedAt))
                .OrderByDescending(item => item.RssiDbm).ThenBy(item => item.Bssid, StringComparer.Ordinal).ToArray();
            return Result(new ScanInfo(options.Cached ? "cached" : "completed", ContractJson.Timestamp(started),
                ContractJson.Timestamp(completed < started ? started : completed), null), observations);
        }
        catch (WlanException error) { return Failed(error.ContractCode, error.Message); }
        catch (TimeoutException) { return Failed("scan_timeout", "Windows did not report scan completion before the timeout."); }
        catch (PlatformNotSupportedException error) { return Failed("unsupported", error.Message); }
        catch (InvalidDataException error) { return Failed("backend_error", error.Message); }

        ScanResult Result(ScanInfo scan, IReadOnlyList<Observation> observations) => new(
            "0.1.0", new BackendInfo(), new ScanInterface(interfaceId), new ScanCapabilities(), scan, observations);
        ScanResult Failed(string code, string message) => Result(
            new ScanInfo("failed", ContractJson.Timestamp(started), null, new ScanError(code, message)), []);
    }

    internal static Observation Normalize(BssObservation entry, string? connectedBssid,
        DateTimeOffset now, DateTimeOffset? requestedAt)
    {
        if (entry.Ssid.Length > 32 || entry.Bssid.Length != 6 || entry.RssiDbm > 0 || entry.Quality > 100)
            throw new InvalidDataException("Windows returned an invalid SSID, BSSID or signal measurement.");

        string? bssid = entry.Bssid.All(value => value == 0) || entry.Bssid.All(value => value == 255)
            ? null : string.Join(':', entry.Bssid.Select(value => value.ToString("x2")));
        DateTimeOffset? seen = null;
        if (entry.HostTimestamp > 0 && entry.HostTimestamp <= long.MaxValue)
        {
            try { seen = new DateTimeOffset(DateTime.FromFileTimeUtc((long)entry.HostTimestamp)); }
            catch (ArgumentOutOfRangeException) { }
        }
        // FILETIME is a wall-clock timestamp. Future values or clock changes cannot prove freshness.
        if (seen > now || (requestedAt is { } request && now < request)) seen = null;
        long? age = seen.HasValue ? (now.UtcTicks - seen.Value.UtcTicks) / TimeSpan.TicksPerMillisecond : null;
        string freshness = requestedAt is null ? "cached" : seen is null ? "unknown"
            : seen < requestedAt ? "cached" : seen > requestedAt ? "fresh" : "unknown";

        return new Observation(Encoding.UTF8.GetString(entry.Ssid), Convert.ToBase64String(entry.Ssid), bssid,
            entry.RssiDbm, (int)entry.Quality, null,
            entry.FrequencyKhz > 0 && entry.FrequencyKhz % 1000 == 0 ? checked((int)(entry.FrequencyKhz / 1000)) : null,
            null, bssid is not null && connectedBssid is not null ? bssid == connectedBssid : null, freshness, age);
    }
}

internal sealed record BssObservation(byte[] Ssid, byte[] Bssid, int RssiDbm, uint Quality,
    uint FrequencyKhz, ulong HostTimestamp);

internal interface IWlanClient : IDisposable
{
    IReadOnlyList<WirelessInterface> GetInterfaces();
    Task<DateTimeOffset> RequestScanAsync(Guid id, TimeSpan timeout, CancellationToken cancellationToken);
    IReadOnlyList<BssObservation> ReadBss(Guid id);
    string? ReadConnectedBssid(Guid id);
}
