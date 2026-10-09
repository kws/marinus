# Architecture

Marinus is one repository with independently buildable platform backends, a
shared contract and a shared survey/heatmap core. Backend languages and release
cadences can differ; observations and behavior must remain compatible with the
contract version each backend advertises.

## Repository layout

```text
backends/macos/    Swift scanner, CLI, app packaging and tests
backends/linux/    NetworkManager scanner, Python entry points and tests
backends/windows/ C# Native WLAN library, CLI, publishing and synthetic tests
contracts/        Draft schema, behavior specification and synthetic fixtures
heatmaps/         Planned shared survey/heatmap core
docs/             Architecture, roadmap and import provenance
licenses/         Complete upstream license notices
```

The macOS and Linux prototypes keep their existing formats. Windows exposes
the draft contract through its library and CLI. The draft remains subject to
change; once all adapters conform, the CLI and library should expose the same
scan object. Format validation alone
cannot prove that a scan completed, a reading is fresh or a unit has the intended
meaning; backend behavior needs conformance tests as well.

## Backend responsibilities

- List interfaces and capabilities, request scans and report completion/errors.
- Retain individual BSSIDs and hidden/unknown identifiers rather than merging
  observations by SSID.
- Preserve native signal measurements and units. Missing data is `null`, not
  zero, a fabricated dBm value or an arbitrary percentage.
- Distinguish explicitly cached reads, completed scan requests and the freshness
  of individual observations. A completed request can leave cached entries.
- Report permissions through structured errors; never silently substitute cached
  measurements when a caller asked for a fresh scan.

The macOS prototype runs the same executable in an app through LaunchServices
to obtain its macOS privacy identity. A private Unix socket returns the result
to the terminal. It retains the original diagnostic commands, including explicit
Keychain lookup; credentials are outside the planned survey contract.

The Linux prototype requests scans through NetworkManager's system D-Bus API
and reads results as the invoking user. NetworkManager provides the privileged
service and PolicyKit authorization. The optional diagnostic sudo path elevates
only a fixed scan request, not the collector. Do not install a setuid collector
or automatic policy bypass as part of normal builds.

The Windows backend uses Native WLAN scan notifications and BSS results. It
retains native RSSI, link quality and raw SSID bytes, and uses host receive
timestamps for observation age/freshness. Its watch command exports JSON Lines
for repeated measurements; consent/permissions still require hardware checks.
A replay backend is also planned so downstream tools can develop without radios.

## Survey and heatmap responsibilities

The shared core will pair observations with sample positions, floor-plan scale,
timestamps and survey metadata, then interpolate and render/export coverage.
Front ends can wrap that core without implementing platform scan logic.

Relative signal is sufficient for a useful heatmap. Keep the scale fixed within
a survey: normalizing each scan against its strongest AP would hide weak areas.
Record device/backend and measurement units, and do not imply identical values
across operating systems or adapters. Unknown/cached readings and areas far from
actual samples should remain visible as uncertainty in the resulting map.

## Versioning

`contract_version` describes data shape **and documented behavior**.
`backend_version` identifies an implementation release. Capabilities describe
supported measurements rather than depending on populated results in a scan.
The draft is `0.1.0`; stabilize it before a `1.0.0` contract commitment. After
stabilization, breaking changes require a new major contract version; compatible
optional additions and fixes must retain the meanings of existing fields.
