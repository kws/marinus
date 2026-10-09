# Marinus Desktop

An initial Tauri 2 / TypeScript application for interface selection, fresh scans,
explicit cache reads, cancellation, filtering and JSON export. The synthetic
demo is clearly labeled and usable without a radio. Floor-plan surveys, heatmap
rendering and updates remain later milestones.

The window uses compact toolbars, a fixed status bar and a full-height access-point
table. Only the table scrolls, with column headings kept visible; the rest of the
window stays fixed. Controls and table colors follow the system light/dark theme.

## Develop

Requires Node.js 22.12+ and Rust (the project pins 1.90.0). Install the platform's
[Tauri prerequisites](https://v2.tauri.app/start/prerequisites/), plus the scanner's
build/runtime requirements: Swift on macOS, .NET 10 SDK on Windows, or distro
Python 3.10+, `python3-dbus` and NetworkManager on Linux.

```sh
cd desktop
npm ci
npm run desktop:dev
```

The preparation step builds and bundles the complete Swift privacy app on macOS,
a self-contained scanner on Windows, or the collector source on Linux. Linux
uses `/usr/bin/python3` to reach the distribution's D-Bus binding. Windows does
not require Python or .NET to be installed by end users. Dependency notices are
collected from the locked Rust resolution and installed frontend API.

For a browser-only preview, run `npm run dev` and visit the reported local URL.
That preview uses synthetic observations. Native scans require the desktop app.

## Build

```sh
npm test
npm run build
cargo test --locked --manifest-path src-tauri/Cargo.toml
npm run release -- --development
```

Development packaging produces an ad-hoc signed app/unsigned DMG on macOS,
unsigned NSIS setup EXE on Windows, or a Debian package on Linux. Artifacts are
under `src-tauri/target/release/bundle/`. See [release packaging](../docs/packaging.md)
for signed builds and the remaining platform checks.

## Integration

The webview can invoke fixed enumeration, scan, cancellation and save operations.
It cannot choose an executable or execute arbitrary shell commands. Only one
backend operation runs at a time; cancellation or timeout kills its CLI process.
The macOS worker also exits when its CLI parent disappears. Scans do not start
automatically when the window opens.

The nested Swift app retains bundle ID `io.github.kws.marinus`. The GUI has the
separate ID `io.github.kws.marinus.desktop`; location consent belongs to the Swift
scanner. Keep the nested app intact. Packaged permission attribution and upgrades
still need checks with stable Developer ID signatures on supported macOS versions.

JSON export uses a native save dialog and refuses to overwrite an existing file.
Signal meters use fixed display ranges, while labels retain native dBm/percent
units. Unknown observation freshness stays visible. These meters do not claim
measurement calibration between platforms.

## Windows hardware validation

The unsigned x64 NSIS development build was installed and tested on Windows 11
with an Intel AX201 on 2026-10-09. Installation and the GUI ran under a normal
desktop user token. Interface discovery, live scans, explicit cached reads,
filtering, cancellation and a subsequent scan passed. JSON exported through the
native save dialog passed the shared schema and measurement checks. The 24
Windows backend tests, three frontend tests and three Rust tests also passed,
along with formatting and Clippy checks.

That check exposed an initial window extending below the screen at 150% display
scaling. Windows startup now fits the window and its minimum size to the monitor
work area when needed; the installed replacement was checked against the actual
window bounds, then scanned and exported again. Signed distribution, denied
location consent, other adapters, ARM64 and upgrades from earlier releases still
need their own checks. Identifying captures and host-specific test helpers stay
outside the source tree.
