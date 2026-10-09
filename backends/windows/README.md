# Windows scanner

A C# library and CLI using Windows' Native WLAN API. Requires a Windows version
supported by .NET 10, an enabled Wi-Fi adapter and the WLAN AutoConfig service.
Build with the .NET 10 SDK. The self-contained executable includes its .NET runtime; Python
is needed only for development schema checks. There are no external NuGet
runtime dependencies.

## Build and run

From a normal PowerShell window at the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File backends/windows/scripts/build.ps1
$marinus = '.\backends\windows\dist\marinus.exe'
& $marinus interfaces
& $marinus scan
& $marinus scan --json
& $marinus watch --interval 5 --count 10 --output .\captures\walk.jsonl
```

The build script publishes for Windows x64 by default. Pass `-Runtime win-arm64`
for ARM64, or `-FrameworkDependent` to use an installed .NET 10 runtime. The
execution-policy option affects only the script's PowerShell process.
Keep the distribution's `LICENSE`, `THIRD_PARTY_NOTICES.md` and `licenses/`
directory with the executable, including the bundled .NET runtime notices.

`scan` shows a table of individual BSS observations sorted by RSSI, including
hidden networks and duplicate SSIDs. JSON uses the [draft shared contract](../../contracts/README.md).
`watch --json` streams one compact contract object per line, suitable for tools
that record timestamped measurements. The interval is a pause *after* each scan;
scan duration adds to the time between samples. Ctrl+C stops watch (exit 130).

If more than one Wi-Fi interface is available, choose the GUID from `interfaces`:

```powershell
& $marinus scan --interface 11111111-1111-1111-1111-111111111111 --timeout 15 --json
& $marinus scan --cached --output .\captures\cached.json
```

Replace that synthetic GUID with your device's ID. `watch` retains its first
selected interface even if adapters appear or disappear. `--output` writes a
new JSON file for scan, or JSON Lines for watch, and refuses to overwrite an
existing file. Captures can identify nearby networks; keep them local. The
repository ignores `captures/`, `results/` and build output.

## Permissions and failures

Run the executable from your normal desktop session. Windows may ask for
location permission because BSSIDs can reveal location; allow it for this app.
If denied, visit Settings > Privacy & security > Location. Running as an
administrator is not the intended permission flow. See Microsoft's
[Wi-Fi location-access guidance](https://learn.microsoft.com/en-us/windows/win32/nativewifi/wi-fi-access-location-changes).

Fresh scans register ACM notifications, call `WlanScan`, and wait up to the
timeout (15 seconds by default) for the matching interface's scan completion
or failure. The implementation ignores notifications seen before its request
and unrelated interfaces. Native WLAN notifications have no caller request ID;
another caller's concurrent scan cannot be distinguished reliably. Consumers
must also inspect individual observation freshness.

A failed fresh request returns a structured failure and an empty observation
list. It never falls back to the cache. `--cached` is an explicit separate mode
and makes no new scan request. Exit codes are 0 for success, 1 for a scan/backend
or file error, 2 for invalid arguments and 130 for cancellation. `watch` stops
on its first failed scan after writing that failure record.

## Measurements

- Native RSSI is retained in dBm. Native link quality is a separate 0–100 value;
  it is never converted to dBm or normalized against the strongest AP.
- Each BSSID remains a separate observation. Raw SSID bytes are preserved in
  base64 alongside UTF-8 display text; an empty SSID is known hidden/empty.
- Native center frequency is converted from kHz to MHz. Noise, channel width
  and driver identity are currently unknown (`null`) and are not invented.
- Connection identity uses an optional current-connection query. If Windows
  cannot provide it, `connected` is `null` for every observation.
- The host receive timestamp is FILETIME (100-nanosecond units since 1601).
  Age and per-observation freshness use that timestamp, not the AP's beacon
  clock. Entries predating the request are cached; later entries are fresh;
  missing, invalid, future or equal timestamps are unknown. An explicit cached
  read labels entries cached. Driver sampling resolution is unspecified, so
  `last_seen_resolution_ms` remains `null`.

These fields describe the driver's observations; scan completion does not
guarantee every entry is new. See [Microsoft's BSS structure reference](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/ns-wlanapi-wlan_bss_entry).

## Library

Reference `src/Marinus.Windows/Marinus.Windows.csproj` from a .NET 10 project:

```csharp
using Marinus.Windows;

var scanner = new WindowsScanner();
var interfaces = scanner.GetInterfaces();
var result = await scanner.ScanAsync(new ScanOptions(InterfaceId: interfaces[0].Id));
Console.WriteLine(ContractJson.Serialize(result, indented: true));
```

Each scan owns and disposes its native client handle; the library accepts
cancellation tokens and returns the same object the CLI serializes. Interface
enumeration can throw `WlanException`; scan errors use `result.Scan.Error`.
The contract and library are initial 0.1.0 APIs and remain subject to change.

## Tests

Synthetic tests run on Windows, macOS or Linux without a radio or permission
dialog. They cover native buffer bounds/layout, binary identifiers, measurement
mapping, freshness, permissions, timeout, notification matching, cancellation,
interface selection, streaming export and capture preservation. The runner
uses the SDK only; no test-framework package is needed.

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
powershell -NoProfile -ExecutionPolicy Bypass -File backends/windows/scripts/test.ps1 -Python .\.venv\Scripts\python.exe
```

On macOS/Linux with .NET 10 and the Python development environment available:
`make test-windows`. Windows CI runs synthetic tests, validates generated
success/cache/failure objects against the shared schema, and publishes the CLI.

Initial hardware validation on 2026-10-09 passed on Windows 11 with an Intel
AX201 adapter: fresh scans, explicit cached reads, repeated JSON Lines captures
and a scan from a normal, unelevated desktop session after location consent.
Two paired scans with a nearby Mac found 18–19 shared BSSIDs per pair. Windows
returned both fresh and cached observations; comparisons excluded cached
readings. Across 31 fresh matched readings, the median Windows-minus-Mac RSSI
difference was 1 dB, while individual networks varied. These checks establish
collection feasibility on the tested hardware, rather than calibration between
adapters. Identifying scan captures remain outside the repository.

Further live checks include consent denial, multiple adapters, radio-off
behavior, additional drivers and a real walk-around survey. JSON captures can be validated with
`python scripts/check-contracts.py captures/walk.jsonl`; that verifies shape and
measurement invariants rather than radio behavior.
