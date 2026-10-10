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
- Native channel frequency is converted from kHz to MHz. Noise and driver
  identity are currently unknown (`null`) and are not invented.
- Advertised operating width is decoded from the BSSID's HT/VHT/HE/EHT operation
  elements, including 6 GHz HE and 320 MHz EHT operation when supplied by the
  driver. PHY capability elements are not used to guess the operating width.
  Missing, malformed or unrecognized data stays `null` without discarding the
  BSSID's other measurements. Non-contiguous 80+80 MHz operation stays unknown
  because the draft contract has no way to distinguish it from contiguous
  160 MHz. The parser reports the nominal EHT width, including when a disabled
  subchannel bitmap is present; it does not report puncturing or channel spans.
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

Width parsing is covered by synthetic operation elements and native-buffer
bounds/offset tests. Live Intel AX201 scans also verified 20, 40, 80 and 160 MHz
width collection; 6 GHz HE and 320 MHz EHT parsing still have synthetic coverage
only. See the hardware checks below.

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

On 2026-10-10, the current width collector was built and tested in a separate
directory on `bb-108`, running Windows 11 build 26200 with an Intel AX201 and
.NET SDK 10.0.401. All 29 synthetic backend tests passed, and the Release build
completed without warnings or errors. A cached read returned 12 BSSIDs; two
fresh scans returned 21 and 23 BSSIDs, respectively, across 2.4 GHz and 5 GHz.
Both fresh scans collected advertised widths of 20, 40, 80 and 160 MHz. They
retained 18/17 fresh observations and 3/6 cached observations, respectively.

The second fresh scan ran in the active desktop session with an unelevated user
token and completed successfully. All four live interface/scan envelopes and
seven generated fixtures passed the shared validator. The desktop decoder and
radio helpers accepted each capture and displayed the expected band, primary
channel and advertised width for each BSSID. The temporary desktop test task
was removed; the installed GUI and main checkout were not modified. Private
captures and test sources remain outside the repository. No 6 GHz observations
were available on this adapter, so 6 GHz HE and 320 MHz EHT width collection
still need an appropriate hardware check.

Further live checks include consent denial, multiple adapters, radio-off
behavior, additional drivers and a real walk-around survey. JSON captures can be validated with
`python scripts/check-contracts.py captures/walk.jsonl`; that verifies shape and
measurement invariants rather than radio behavior.

## Shared protocol and installers

`interfaces --json` returns a versioned enumeration envelope, including structured
errors. Scan/watch retain their draft envelope and JSON Lines behavior. See the
[common CLI protocol](../../contracts/cli.md), [desktop guide](../../desktop/README.md)
and [installer/signing instructions](../../docs/packaging.md).
