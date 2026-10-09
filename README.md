# Marinus

Cross-platform Wi-Fi surveying and heatmaps, with a CLI and library for building
survey tools.

Marinus is named after **Marinus of Tyre**, an early cartographer. The goal is to
make useful maps of wireless coverage from repeated observations, with consistent
data that applications can consume on macOS, Linux and Windows.

## Current state

This repository contains functioning macOS, Linux and Windows scanners. Their
command interfaces and JSON output are **not yet unified**: Windows implements
the draft shared contract, while macOS and Linux retain their prototype formats.
The cross-platform shared library API and heatmap engine are planned work.

| Component | Status | Implementation |
| --- | --- | --- |
| macOS scanning | Imported prototype; macOS 13+ | Swift, CoreWLAN and a signed app bundle |
| Linux scanning | Prototype tested on Pop!_OS 22.04 | Python, NetworkManager and system D-Bus |
| Windows scanning | Initial CLI and C# library; scan, cache and watch | .NET 10 and Native WLAN API |
| Shared scan contract | Draft; implemented by Windows | JSON Schema and synthetic examples |
| Heatmap engine | Planned core component | Survey samples, coordinates and interpolation |

macOS and Windows report native RSSI in dBm. Linux preserves NetworkManager's
native signal percentage. These are useful for relative coverage; they are not
assumed to be calibrated to each other. Preserve the original units and use a
consistent scale throughout a survey.

## Try the prototypes

### macOS

Install Apple's Command Line Tools or Xcode with Swift 5.9 or newer, then:

```sh
make build-macos
./backends/macos/dist/marinus scan --bssids --json
./backends/macos/dist/marinus help
```

The command lives inside `Marinus.app`; keep the bundle intact. macOS must grant
Location Services access to **Marinus**. Its app identity is distinct from
MacWiFi, so an existing MacWiFi permission does not grant Marinus access.
See the [macOS backend guide](backends/macos/README.md) for signing and commands.
Use `--bssids` for survey measurements: the inherited default summary can include
saved networks that were not observed.

### Linux

Requires Python 3.10+, NetworkManager and the distribution's Python `dbus` module:

```sh
python3 backends/linux/wifi_scan.py --interfaces
python3 backends/linux/wifi_scan.py --interface wlan0
python3 backends/linux/wifi_scan.py --cached
```

Replace `wlan0` with your interface. Fresh scan authorization uses the existing
NetworkManager/PolicyKit policy. The [Linux guide](backends/linux/README.md)
documents permissions, freshness and an explicit diagnostic sudo option.

### Windows

Build with the .NET 10 SDK, then run the self-contained CLI from normal PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File backends/windows/scripts/build.ps1
.\backends\windows\dist\marinus.exe scan
.\backends\windows\dist\marinus.exe scan --json
.\backends\windows\dist\marinus.exe watch --count 10 --output .\captures\walk.jsonl
```

Allow Windows location access when prompted. The [Windows guide](backends/windows/README.md)
covers interface selection, permissions, cached reads, JSON Lines export and the
C# library. Heatmap rendering and survey positions are future work.

## Development

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements-dev.txt
make test
make check
```

Tests use synthetic observations; they do not scan nearby networks or access
the Keychain. On macOS, `make check` also builds and verifies the app and tests
a LaunchServices round trip without requesting radio or Keychain permissions.
With the .NET 10 SDK installed, `make test-windows` also checks the Windows
library/CLI and generated contract output on macOS/Linux. Windows has a
PowerShell test script in its backend guide. GitHub Actions checks all three
backends and draft fixtures; synthetic tests do not require Wi-Fi hardware.

Start with the [architecture](docs/architecture.md),
[draft contract](contracts/README.md), [roadmap](docs/roadmap.md), and
[contribution guide](CONTRIBUTING.md).

## Origins and license

Marinus is licensed under [MIT](LICENSE). The macOS prototype derives from
[jaisonerick/macwifi](https://github.com/jaisonerick/macwifi) through the
[kws/macwifi Swift fork](https://github.com/kws/macwifi), with command/output
behavior originating in
[jaisonerick/macwifi-cli](https://github.com/jaisonerick/macwifi-cli).

Upstream copyright notices and complete license texts are retained in
[third-party notices](THIRD_PARTY_NOTICES.md) and [licenses](licenses/).
The [provenance record](docs/provenance.md) identifies the source commit and
imported files.
