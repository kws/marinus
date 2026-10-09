# Marinus

Cross-platform Wi-Fi surveying and heatmaps, with a CLI and library for building
survey tools.

Marinus is named after **Marinus of Tyre**, an early cartographer. The goal is to
make useful maps of wireless coverage from repeated observations, with consistent
data that applications can consume on macOS, Linux and Windows.

## Current state

This repository contains functioning macOS, Linux and Windows scanners. Their survey commands now share a draft JSON contract and common
interface/scan/watch behavior. An initial Tauri desktop explorer provides
interface selection, scans, cache reads and export. The shared survey/heatmap
engine and installed-platform release validation remain planned work.

| Component | Status | Implementation |
| --- | --- | --- |
| macOS scanning | Imported prototype; macOS 13+ | Swift, CoreWLAN and a signed app bundle |
| Linux scanning | Prototype tested on Pop!_OS 22.04 | Python, NetworkManager and system D-Bus |
| Windows scanning | Initial CLI and C# library; scan, cache and watch | .NET 10 and Native WLAN API |
| Shared scan contract | Draft; implemented by all three adapters | JSON Schema, generated-output and behavior checks |
| Desktop GUI | Initial explorer and synthetic demo | Tauri 2 and TypeScript |
| Installers | Development scripts and signing hooks | macOS PKG/DMG, Windows setup EXE, Linux DEB |
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
./backends/macos/dist/marinus scan --json
./backends/macos/dist/marinus help
```

The command lives inside `Marinus.app`; keep the bundle intact. macOS must grant
Location Services access to **Marinus**. Its app identity is distinct from
MacWiFi, so an existing MacWiFi permission does not grant Marinus access.
See the [macOS backend guide](backends/macos/README.md) for signing and commands.
Survey scans retain every observed BSSID. The original summary/output is available
with `scan --legacy`; it can include saved networks that were not observed.

### Linux

Requires Python 3.10+, NetworkManager and the distribution's Python `dbus` module:

```sh
python3 backends/linux/wifi_scan.py interfaces --json
python3 backends/linux/wifi_scan.py scan --interface wlan0 --json
python3 backends/linux/wifi_scan.py scan --cached --json
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

## Desktop and installers

```sh
cd desktop
npm ci
npm run desktop:dev
```

Requires the platform build tools and Rust/Node; see the [desktop guide](desktop/README.md).
`npm run dev` provides a browser preview using a labeled synthetic demo.
Build development installers with [the packaging guide](docs/packaging.md).
Public signing requires release credentials and installed-platform validation.

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
