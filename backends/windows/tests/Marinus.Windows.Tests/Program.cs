using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Marinus.Cli;
using Marinus.Windows;

var tests = new List<(string Name, Func<Task> Run)>();
var start = DateTimeOffset.Parse("2026-01-01T12:00:00Z");
var id = Guid.Parse("11111111-1111-1111-1111-111111111111");
var otherId = Guid.Parse("22222222-2222-2222-2222-222222222222");
var adapter = new WirelessInterface(id, "Synthetic Wi-Fi adapter", "connected");
var fixtures = new Dictionary<string, ScanResult>();

void Test(string name, Action run) => tests.Add((name, () => { run(); return Task.CompletedTask; }));
void AsyncTest(string name, Func<Task> run) => tests.Add((name, run));
void Assert(bool condition, string message = "Assertion failed") { if (!condition) throw new Exception(message); }
BssObservation Entry(byte[]? ssid = null, int rssi = -55, uint quality = 72, DateTimeOffset? seen = null,
    byte lastOctet = 1, ulong? timestamp = null) => new(ssid ?? Encoding.UTF8.GetBytes("ExampleNet"),
    [2, 0, 0, 0, 0, lastOctet], rssi, quality, 5180000,
    timestamp ?? (ulong)(seen ?? start.AddSeconds(1)).UtcDateTime.ToFileTimeUtc());
byte[] Ie(byte id, params byte[] data) => [id, checked((byte)data.Length), .. data];
byte[] Ht(byte flags) => Ie(61, [36, flags, .. new byte[20]]);
byte[] Vht(byte width, byte segment0 = 42, byte segment1 = 0) => Ie(192, width, segment0, segment1, 0, 0);
(WindowsScanner Scanner, FakeClient Client) Setup()
{
    var clock = new FakeClock { Now = start };
    var client = new FakeClient { Interfaces = [adapter], Entries = [Entry()], RequestedAt = start,
        OnRequested = () => clock.Now = start.AddSeconds(2), ConnectedBssid = "02:00:00:00:00:01" };
    return (new WindowsScanner(() => client, clock), client);
}

AsyncTest("Native measurements, connection and contract envelope", async () =>
{
    var (scanner, client) = Setup();
    var result = await scanner.ScanAsync();
    fixtures["windows-completed"] = result;
    var row = result.Observations.Single();
    Assert(result.ContractVersion == "0.1.0" && result.Backend.Platform == "windows");
    Assert(result.Scan.Status == "completed" && result.Scan.Error is null);
    Assert(row.RssiDbm == -55 && row.StrengthPercent == 72 && row.FrequencyMhz == 5180);
    Assert(row.Bssid == "02:00:00:00:00:01" && row.Connected == true);
    Assert(row.NoiseDbm is null && row.ChannelWidthMhz is null && result.Interface.Driver is null);
    Assert(result.Capabilities.LastSeenResolutionMs is null && !result.Capabilities.NoiseDbm);
    Assert(result.Capabilities.ChannelWidthMhz);
    Assert(client.Calls.SequenceEqual(["interfaces", "scan", "bss", "connection", "dispose"]));
    using var json = JsonDocument.Parse(ContractJson.Serialize(result));
    Assert(json.RootElement.GetProperty("scan").GetProperty("started_at").GetString()!.EndsWith('Z'));
});

Test("HT and VHT operation widths override PHY capabilities", () =>
{
    // A capability element advertising 40 MHz support must not imply operation at 40 MHz.
    byte[] capability = Ie(45, [2, .. new byte[25]]);
    Assert(AdvertisedChannelWidth.Read(capability, 2412000) is null);
    Assert(AdvertisedChannelWidth.Read([.. capability, .. Ht(0)], 2412000) == 20);
    Assert(AdvertisedChannelWidth.Read(Ht(5), 2412000) == 40);
    Assert(AdvertisedChannelWidth.Read(Ht(7), 2412000) == 40);
    Assert(AdvertisedChannelWidth.Read(Ht(6), 2412000) is null);
    Assert(AdvertisedChannelWidth.Read([.. Ht(5), .. Vht(0)], 5180000) == 40);
    Assert(AdvertisedChannelWidth.Read(Vht(0), 5180000) is null);
    Assert(AdvertisedChannelWidth.Read([.. Ht(5), .. Vht(1)], 5180000) == 80);
    Assert(AdvertisedChannelWidth.Read(Vht(1, 42, 50), 5180000) == 160);
    Assert(AdvertisedChannelWidth.Read(Vht(2, 50), 5180000) == 160);
    Assert(AdvertisedChannelWidth.Read(Vht(1, 42, 106), 5180000) is null);
    Assert(AdvertisedChannelWidth.Read(Vht(3, 42, 106), 5180000) is null);
    Assert(AdvertisedChannelWidth.Read(Vht(7), 5180000) is null);
    Assert(AdvertisedChannelWidth.Read(Vht(1, 0), 5180000) is null);
});

Test("HE optional fields and EHT operating widths support 6 GHz and Wi-Fi 7", () =>
{
    byte[] he80 = Ie(255, 36, 0, 0, 2, 0, 0, 0, 5, 2, 7, 0, 0);
    byte[] he160 = Ie(255, 36, 0, 0, 2, 0, 0, 0, 5, 3, 7, 15, 0);
    byte[] he160Original = Ie(255, 36, 0, 0, 2, 0, 0, 0, 5, 3, 15, 0, 0);
    byte[] heSplit = Ie(255, 36, 0, 0, 2, 0, 0, 0, 5, 3, 7, 39, 0);
    // Embedded VHT information and a co-hosted-BSS byte precede the 6 GHz fields.
    byte[] heOptional = Ie(255, 36, 0, 0xc0, 2, 0, 0, 0, 1, 42, 0, 3, 5, 2, 7, 0, 0);
    Assert(AdvertisedChannelWidth.Read(he80, 5975000) == 80);
    Assert(AdvertisedChannelWidth.Read(he160, 5975000) == 160);
    Assert(AdvertisedChannelWidth.Read(he160Original, 5975000) == 160);
    Assert(AdvertisedChannelWidth.Read(heSplit, 5975000) is null);
    Assert(AdvertisedChannelWidth.Read(heOptional, 5975000) == 80);
    Assert(AdvertisedChannelWidth.Read(Ie(255, 36, 0, 0, 2, 0, 0, 0, 5, 0, 5, 0, 0), 5975000) == 20);
    Assert(AdvertisedChannelWidth.Read(Ie(255, 36, 0, 0, 2, 0, 0, 0, 5, 1, 3, 0, 0), 5975000) == 40);
    Assert(AdvertisedChannelWidth.Read(Ie(255, 36, 0, 0x40, 0, 0, 0, 0, 1, 42, 0), 5180000) == 80);
    Assert(AdvertisedChannelWidth.Read(Ht(0), 5975000) is null);
    byte[] eht320 = Ie(255, 106, 1, 0, 0, 0, 0, 4, 31, 63);
    Assert(AdvertisedChannelWidth.Read([.. he80, .. eht320], 5975000) == 320);
    Assert(AdvertisedChannelWidth.Read(eht320, 5180000) is null);
    Assert(AdvertisedChannelWidth.Read([.. he80, .. Ie(255, 106, 2, 0, 0, 0, 0)], 5975000) is null);
    Assert(AdvertisedChannelWidth.Read(Ie(255, 106, 3, 0, 0, 0, 0, 3, 7, 15, 0, 0), 5975000) == 160);
    // If EHT has no separate operation info, the advertised HE operation still applies.
    Assert(AdvertisedChannelWidth.Read([.. he80, .. Ie(255, 106, 0, 0, 0, 0, 0)], 5975000) == 80);
});

Test("Missing, malformed and unsupported operation data remain unknown", () =>
{
    foreach (byte[] ies in new byte[][]
    {
        [], [61], [61, 22, 36, 0], Ie(61, 36, 0), Ie(192, 1, 42),
        [.. Vht(1), 255], [.. Ht(0), .. Ht(5)], Ie(255),
        Ie(255, 36, 0, 0x40, 2, 0, 0, 0), // HE optional data truncated
        Ie(255, 106, 1, 0, 0, 0, 0), // EHT operation information absent
        Ie(255, 106, 3, 0, 0, 0, 0, 4, 31, 63), // Bitmap truncated
        Ie(255, 106, 1, 0, 0, 0, 0, 7, 31, 63), // Reserved EHT width
    })
        foreach (uint frequency in new uint[] { 2412000, 5180000, 5975000 })
            Assert(AdvertisedChannelWidth.Read(ies, frequency) is null);
});

AsyncTest("Advertised widths survive normalization and JSON export for individual BSSIDs", async () =>
{
    var (scanner, client) = Setup();
    client.Entries = [Entry() with { ChannelWidthMhz = 80 }, Entry(lastOctet: 2)];
    var result = await scanner.ScanAsync();
    Assert(result.Observations[0].ChannelWidthMhz == 80 && result.Observations[1].ChannelWidthMhz is null);
    using var json = JsonDocument.Parse(ContractJson.Serialize(result));
    Assert(json.RootElement.GetProperty("observations")[0].GetProperty("channel_width_mhz").GetInt32() == 80);
    Assert(json.RootElement.GetProperty("observations")[1].GetProperty("channel_width_mhz").ValueKind == JsonValueKind.Null);
    fixtures["windows-widths"] = result;
});

Test("Freshness uses host FILETIME rather than request completion", () =>
{
    var now = start.AddSeconds(2);
    var fresh = WindowsScanner.Normalize(Entry(seen: start.AddSeconds(1)), null, now, start);
    var old = WindowsScanner.Normalize(Entry(seen: start.AddSeconds(-5)), null, now, start);
    var equal = WindowsScanner.Normalize(Entry(seen: start), null, now, start);
    Assert(fresh.Freshness == "fresh" && fresh.LastSeenAgeMs == 1000);
    Assert(old.Freshness == "cached" && old.LastSeenAgeMs == 7000);
    Assert(equal.Freshness == "unknown");
});

Test("Missing, future and invalid timestamps remain unknown", () =>
{
    foreach (var value in new[] { Entry(timestamp: 0), Entry(timestamp: ulong.MaxValue), Entry(seen: start.AddDays(1)) })
    {
        var row = WindowsScanner.Normalize(value, null, start.AddSeconds(2), start);
        Assert(row.Freshness == "unknown" && row.LastSeenAgeMs is null && row.Connected is null);
    }
    Assert(WindowsScanner.Normalize(Entry(), null, start.AddSeconds(-1), start).Freshness == "unknown");
});

AsyncTest("Duplicate SSIDs, hidden networks and non-UTF8 SSID bytes survive", async () =>
{
    var (scanner, client) = Setup();
    client.Entries = [Entry(), Entry(lastOctet: 2), Entry(ssid: [], lastOctet: 3), Entry(ssid: [255, 65], lastOctet: 4)];
    var result = await scanner.ScanAsync();
    Assert(result.Observations.Count == 4);
    Assert(result.Observations.Take(2).All(row => row.Ssid == "ExampleNet"));
    Assert(result.Observations[2].Ssid == "" && result.Observations[2].SsidBytesBase64 == "");
    Assert(Convert.FromBase64String(result.Observations[3].SsidBytesBase64!).SequenceEqual(new byte[] { 255, 65 }));
    Assert(result.Observations[1].Connected == false);
});

AsyncTest("Cached reads never request a scan or claim freshness", async () =>
{
    var (scanner, client) = Setup();
    client.Entries = [Entry(seen: start.AddSeconds(-1))];
    var result = await scanner.ScanAsync(new ScanOptions(Cached: true));
    fixtures["windows-cached"] = result;
    Assert(result.Scan.Status == "cached" && !client.Calls.Contains("scan"));
    Assert(result.Observations.Single().Freshness == "cached");
});

AsyncTest("BSS reads wait for scan completion", async () =>
{
    var (scanner, client) = Setup();
    client.Gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
    var pending = scanner.ScanAsync();
    Assert(!pending.IsCompleted && !client.Calls.Contains("bss"));
    client.Gate.SetResult();
    Assert((await pending).Scan.Status == "completed");
});

foreach (var failure in new (string Name, Exception Error, string Code)[]
{
    ("permission denial", WlanException.FromWin32(5, "WlanScan"), "permission_denied"),
    ("timeout", new TimeoutException(), "scan_timeout"),
    ("scan failure", new WlanException("backend_error", "Scan failure notification"), "backend_error")
})
{
    AsyncTest($"Fresh {failure.Name} has an empty failure envelope, without cached fallback", async () =>
    {
        var (scanner, client) = Setup();
        client.ScanFailure = failure.Error;
        var result = await scanner.ScanAsync();
        fixtures["windows-" + failure.Code] = result;
        Assert(result.Scan.Status == "failed" && result.Scan.Error?.Code == failure.Code);
        Assert(result.Observations.Count == 0 && result.Scan.CompletedAt is null && !client.Calls.Contains("bss"));
        Assert(client.Calls.Last() == "dispose");
    });
}

AsyncTest("BSS permission denial after scan completion still fails", async () =>
{
    var (scanner, client) = Setup();
    client.ReadFailure = WlanException.FromWin32(5, "WlanGetNetworkBssList");
    var result = await scanner.ScanAsync();
    Assert(result.Scan.Error?.Code == "permission_denied" && result.Observations.Count == 0);
});

AsyncTest("Missing and ambiguous interfaces do not initiate scans", async () =>
{
    foreach (var available in new IReadOnlyList<WirelessInterface>[] { [], [adapter, adapter with { Id = otherId }] })
    {
        var (scanner, client) = Setup();
        client.Interfaces = available;
        Assert((await scanner.ScanAsync()).Scan.Error?.Code == "interface_unavailable");
        Assert(!client.Calls.Contains("scan"));
    }
    var (selectedScanner, selectedClient) = Setup();
    Assert((await selectedScanner.ScanAsync(new ScanOptions(InterfaceId: otherId))).Scan.Error?.Code == "interface_unavailable");
    selectedClient.Interfaces = [adapter, adapter with { Id = otherId }];
    Assert((await selectedScanner.ScanAsync(new ScanOptions(InterfaceId: otherId))).Interface.Id == otherId.ToString("D"));
    Assert(selectedClient.LastInterface == otherId);
});

AsyncTest("Cancellation propagates and disposes the native session", async () =>
{
    var (scanner, client) = Setup();
    client.Gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
    using var cancellation = new CancellationTokenSource();
    var pending = scanner.ScanAsync(cancellationToken: cancellation.Token);
    cancellation.Cancel();
    try { await pending; throw new Exception("Cancellation was swallowed"); }
    catch (OperationCanceledException) { }
    Assert(client.Calls.Last() == "dispose" && !client.Calls.Contains("bss"));
});

AsyncTest("Invalid signal measurements fail rather than being clamped", async () =>
{
    foreach (var entry in new[] { Entry(rssi: 5), Entry(quality: 101), Entry(ssid: new byte[33]) })
    {
        var (scanner, client) = Setup();
        client.Entries = [entry];
        Assert((await scanner.ScanAsync()).Scan.Error?.Code == "backend_error");
    }
});

Test("Masked identifiers and unknown frequency stay null", () =>
{
    var row = WindowsScanner.Normalize(Entry() with { Bssid = new byte[6], FrequencyKhz = 0 },
        "02:00:00:00:00:01", start.AddSeconds(2), start);
    Assert(row.Bssid is null && row.Connected is null && row.FrequencyMhz is null);
});

Test("Windows native layout matches the x64 WLAN ABI", () =>
{
    Assert(Marshal.SizeOf<Native.BssEntry>() == 360);
    Assert(Marshal.OffsetOf<Native.BssEntry>(nameof(Native.BssEntry.HostTimestamp)).ToInt32() == 80);
    Assert(Marshal.OffsetOf<Native.BssEntry>(nameof(Native.BssEntry.CenterFrequencyKhz)).ToInt32() == 92);
    Assert(Marshal.SizeOf<Native.InterfaceInfo>() == 532);
    Assert(Marshal.SizeOf<Native.ConnectionAttributes>() == 604);
});

Test("Native BSS buffer parsing preserves binary fields and validates bounds", () =>
{
    var memory = Marshal.AllocHGlobal(368);
    try
    {
        Marshal.WriteInt32(memory, 368);
        Marshal.WriteInt32(memory, 4, 1);
        var native = new Native.BssEntry
        {
            Ssid = new Native.Ssid { Length = 2, Bytes = new byte[32] }, Bssid = [2, 0, 0, 0, 0, 1],
            Rssi = -67, LinkQuality = 56, HostTimestamp = (ulong)start.UtcDateTime.ToFileTimeUtc(),
            CenterFrequencyKhz = 2412000, Rates = new Native.RateSet { Rates = new ushort[126] }
        };
        native.Ssid.Bytes[0] = 255; native.Ssid.Bytes[1] = 0;
        Marshal.StructureToPtr(native, IntPtr.Add(memory, 8), false);
        var row = BssParser.Read(memory).Single();
        Assert(row.Ssid.SequenceEqual(new byte[] { 255, 0 }) && row.RssiDbm == -67 && row.FrequencyKhz == 2412000);
        foreach (var total in new[] { 7, 367 })
        {
            Marshal.WriteInt32(memory, total);
            try { BssParser.Read(memory); throw new Exception("Truncated buffer accepted"); }
            catch (InvalidDataException) { }
        }
        Marshal.WriteInt32(memory, 368);
        native.Ssid.Length = 33;
        Marshal.StructureToPtr(native, IntPtr.Add(memory, 8), false);
        try { BssParser.Read(memory); throw new Exception("Oversized SSID accepted"); }
        catch (InvalidDataException) { }
    }
    finally { Marshal.FreeHGlobal(memory); }
});

Test("Native IE buffers use per-entry offsets and keep bad optional data unknown", () =>
{
    int stride = Marshal.SizeOf<Native.BssEntry>();
    byte[][] ies = [Ht(0), Vht(1)];
    int dataStart = 8 + 2 * stride;
    int total = dataStart + ies.Sum(data => data.Length);
    var memory = Marshal.AllocHGlobal(total);
    try
    {
        Marshal.WriteInt32(memory, total);
        Marshal.WriteInt32(memory, 4, 2);
        for (int index = 0; index < 2; index++)
        {
            int offset = 8 + index * stride;
            var native = new Native.BssEntry
            {
                Ssid = new Native.Ssid { Length = 0, Bytes = new byte[32] },
                Bssid = [2, 0, 0, 0, 0, (byte)(index + 1)], Rssi = -55, LinkQuality = 70,
                CenterFrequencyKhz = 5180000, Rates = new Native.RateSet { Rates = new ushort[126] },
                IeOffset = (uint)(dataStart - offset), IeSize = (uint)ies[index].Length
            };
            Marshal.StructureToPtr(native, IntPtr.Add(memory, offset), false);
            Marshal.Copy(ies[index], 0, IntPtr.Add(memory, dataStart), ies[index].Length);
            dataStart += ies[index].Length;
        }
        var rows = BssParser.Read(memory);
        Assert(rows[0].ChannelWidthMhz == 20 && rows[1].ChannelWidthMhz == 80);
        var first = Marshal.PtrToStructure<Native.BssEntry>(IntPtr.Add(memory, 8));
        foreach (var invalid in new (uint Offset, uint Size)[]
        {
            (uint.MaxValue, 22), (first.IeOffset, uint.MaxValue), (0, 22), (first.IeOffset, 0)
        })
        {
            var broken = first;
            broken.IeOffset = invalid.Offset; broken.IeSize = invalid.Size;
            Marshal.StructureToPtr(broken, IntPtr.Add(memory, 8), false);
            rows = BssParser.Read(memory);
            Assert(rows.Count == 2 && rows[0].ChannelWidthMhz is null && rows[1].ChannelWidthMhz == 80);
        }
    }
    finally { Marshal.FreeHGlobal(memory); }
});

AsyncTest("Notification matching rejects pre-request, other-interface and unrelated events", async () =>
{
    var waiter = new ScanNotificationWaiter(id);
    waiter.Notify(8, 7, id, null);
    Assert(!waiter.Completion.IsCompleted);
    waiter.MarkRequested();
    waiter.Notify(8, 7, otherId, null); waiter.Notify(4, 7, id, null); waiter.Notify(8, 9, id, null);
    Assert(!waiter.Completion.IsCompleted);
    waiter.Notify(8, 7, id, null);
    waiter.Notify(8, 8, id, 123);
    Assert(await waiter.Completion is null);
});

AsyncTest("Scan failure notifications retain the reason code", async () =>
{
    var waiter = new ScanNotificationWaiter(id);
    waiter.MarkRequested(); waiter.Notify(8, 8, id, 123);
    Assert(await waiter.Completion == 123);
});

AsyncTest("CLI help and invalid arguments never touch hardware", async () =>
{
    var scanner = new QueueScanner();
    Assert(await CliRunner.RunAsync(["help"], scanner, new StringWriter(), new StringWriter()) == 0);
    foreach (var arguments in new[]
    {
        new[] { "scan", "--interface", "bad" }, new[] { "scan", "--timeout", "NaN" },
        new[] { "watch", "--interval", "0" }, new[] { "watch", "--count", "0" },
        new[] { "watch", "--cached" }, new[] { "scan", "--json", "--json" }, new[] { "scan", "--output" }
    }) Assert(await CliRunner.RunAsync(arguments, scanner, new StringWriter(), new StringWriter()) == 2);
    Assert(scanner.Options.Count == 0);
});

AsyncTest("CLI JSON output preserves the shared failure envelope and exit status", async () =>
{
    var output = new StringWriter();
    var scanner = new QueueScanner(fixtures["windows-permission_denied"]);
    Assert(await CliRunner.RunAsync(["scan", "--json"], scanner, output, new StringWriter()) == 1);
    using var json = JsonDocument.Parse(output.ToString());
    Assert(json.RootElement.GetProperty("observations").GetArrayLength() == 0);
    Assert(json.RootElement.GetProperty("scan").GetProperty("error").GetProperty("code").GetString() == "permission_denied");
});

AsyncTest("Interface enumeration uses a versioned envelope and does not scan", async () =>
{
    var (scanner, client) = Setup();
    var output = new StringWriter();
    Assert(await CliRunner.RunAsync(["interfaces", "--json"], scanner, output, new StringWriter()) == 0);
    using var json = JsonDocument.Parse(output.ToString());
    var value = json.RootElement;
    Assert(value.GetProperty("contract_version").GetString() == "0.1.0");
    Assert(value.GetProperty("interfaces")[0].GetProperty("id").GetString() == id.ToString("D"));
    Assert(value.GetProperty("error").ValueKind == JsonValueKind.Null);
    Assert(client.Calls.SequenceEqual(["interfaces", "dispose"]));
    if (args.Length == 2 && args[0] == "--emit-fixtures")
    {
        Directory.CreateDirectory(args[1]);
        File.WriteAllText(Path.Combine(args[1], "windows-interfaces.json"), output.ToString());
    }
});

AsyncTest("Watch emits JSON Lines and retains its initial adapter", async () =>
{
    string directory = Path.Combine(Path.GetTempPath(), "marinus-tests-" + Guid.NewGuid());
    string path = Path.Combine(directory, "survey.jsonl");
    try
    {
        var output = new StringWriter();
        var result = fixtures["windows-completed"];
        var scanner = new QueueScanner(result, result);
        Assert(await CliRunner.RunAsync(["watch", "--json", "--count", "2", "--interval", "1", "--output", path],
            scanner, output, new StringWriter()) == 0);
        string[] lines = File.ReadAllLines(path);
        Assert(lines.Length == 2 && lines.SequenceEqual(output.ToString().Split(Environment.NewLine, StringSplitOptions.RemoveEmptyEntries)));
        foreach (var line in lines) { using var json = JsonDocument.Parse(line); Assert(json.RootElement.GetProperty("contract_version").GetString() == "0.1.0"); }
        Assert(scanner.Options[0].InterfaceId is null && scanner.Options[1].InterfaceId == id);
    }
    finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
});

AsyncTest("Existing capture files are preserved before a scan is attempted", async () =>
{
    string path = Path.GetTempFileName();
    try
    {
        File.WriteAllText(path, "Existing capture");
        var scanner = new QueueScanner();
        Assert(await CliRunner.RunAsync(["scan", "--output", path], scanner, new StringWriter(), new StringWriter()) == 1);
        Assert(File.ReadAllText(path) == "Existing capture" && scanner.Options.Count == 0);
    }
    finally { File.Delete(path); }
});

Test("Network text cannot inject terminal control sequences", () =>
{
    string escaped = CliRunner.SafeText("Office\u001b[31m\n\u202e");
    Assert(!escaped.Any(char.IsControl) && !escaped.Contains('\u202e') && escaped.Contains("\\u001b"));
});

int failures = 0;
foreach (var test in tests)
{
    try { await test.Run(); Console.WriteLine("PASS " + test.Name); }
    catch (Exception error) { failures++; Console.Error.WriteLine($"FAIL {test.Name}: {error}"); }
}
Console.WriteLine($"{tests.Count - failures}/{tests.Count} tests passed; no live Wi-Fi scans were requested.");
if (failures == 0 && args.Length == 2 && args[0] == "--emit-fixtures")
{
    Directory.CreateDirectory(args[1]);
    foreach (var fixture in fixtures) File.WriteAllText(Path.Combine(args[1], fixture.Key + ".json"), ContractJson.Serialize(fixture.Value, true));
}
return failures == 0 ? 0 : 1;

internal sealed class FakeClock : TimeProvider
{
    internal DateTimeOffset Now;
    public override DateTimeOffset GetUtcNow() => Now;
}

internal sealed class FakeClient : IWlanClient
{
    internal IReadOnlyList<WirelessInterface> Interfaces = [];
    internal IReadOnlyList<BssObservation> Entries = [];
    internal DateTimeOffset RequestedAt;
    internal Action? OnRequested;
    internal string? ConnectedBssid;
    internal Exception? ScanFailure, ReadFailure;
    internal TaskCompletionSource? Gate;
    internal List<string> Calls = [];
    internal Guid LastInterface;
    public IReadOnlyList<WirelessInterface> GetInterfaces() { Calls.Add("interfaces"); return Interfaces; }
    public async Task<DateTimeOffset> RequestScanAsync(Guid id, TimeSpan timeout, CancellationToken cancellationToken)
    {
        Calls.Add("scan"); LastInterface = id;
        if (ScanFailure is not null) throw ScanFailure;
        if (Gate is not null) await Gate.Task.WaitAsync(cancellationToken);
        OnRequested?.Invoke();
        return RequestedAt;
    }
    public IReadOnlyList<BssObservation> ReadBss(Guid id)
    {
        Calls.Add("bss");
        if (ReadFailure is not null) throw ReadFailure;
        return Entries;
    }
    public string? ReadConnectedBssid(Guid id) { Calls.Add("connection"); return ConnectedBssid; }
    public void Dispose() => Calls.Add("dispose");
}

internal sealed class QueueScanner(params ScanResult[] results) : IWindowsScanner
{
    private readonly Queue<ScanResult> _results = new(results);
    internal List<ScanOptions> Options = [];
    public IReadOnlyList<WirelessInterface> GetInterfaces() => [];
    public Task<ScanResult> ScanAsync(ScanOptions? options = null, CancellationToken cancellationToken = default)
    {
        Options.Add(options!);
        return Task.FromResult(_results.Dequeue());
    }
}
