# macOS scanner

A Swift CLI using CoreWLAN on macOS 13+. It is imported from the macwifi Swift
fork; see [provenance](../../docs/provenance.md) and the
[retained notices](../../THIRD_PARTY_NOTICES.md).

## Build and run

From this directory, with Swift 5.9+ and Apple's Command Line Tools or Xcode:

```sh
make build
./dist/marinus scan --json
./dist/marinus info --bssids --json
./dist/marinus help
```

From the repository root, use `make build-macos` and
`./backends/macos/dist/marinus`. The build creates `dist/Marinus.app` and a CLI
symlink into its executable. Keep the bundle intact when moving the command.

Help/version execute directly. Radio operations and explicit Keychain lookups
launch the same executable through LaunchServices, then return stdout, stderr
and status through a private Unix socket. The app identity is
`io.github.kws.marinus`; grant Location Services access to **Marinus** when
prompted. Previous MacWiFi permission does not cover this new identity.

## Legacy diagnostic behavior

The inherited CLI exposes `scan`, `info`, `password`, `help` and `version`.
Only the explicit `password <ssid>` command requests a saved Keychain password;
the scan path does not read credentials. Password lookup is a retained diagnostic
feature, not part of the proposed cross-platform survey API.

| Behavior | `scan --legacy` summary | `scan --legacy --bssids` |
| --- | --- | --- |
| Rows | Strongest result for each nonempty SSID | Every observed CoreWLAN network |
| Connection flag | Matches SSID | Matches a known connected BSSID |
| Unobserved saved networks | Included with zero radio fields | Omitted |
| Hidden SSIDs | Omitted | Retained when returned by CoreWLAN |

The `--legacy` JSON output retains the inherited network array with `ssid`,
`bssid`, `rssi`, `noise`, `channel`, `channel_band`, `channel_width`, `security`,
`phy_mode`, `current` and `saved`. It chooses CoreWLAN's default interface.
Survey `scan --json` uses the shared envelope instead, with explicit nulls and
interface selection; it never adds saved-only placeholders.

## Signing and distribution

The default build is ad-hoc signed. Use a stable signing identity for consistent
macOS permission tracking across builds:

```sh
make build SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
```

For a Developer ID distribution build, configure a notarization profile in
Keychain first, then:

```sh
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE=marinus-notary
./scripts/notarize-app.sh
```

This produces `dist/Marinus.app.zip`. The build packages the root MIT license,
third-party notices and both complete upstream licenses. Signing credentials and
notarization are not used by CI.

Scans default to a 90-second command deadline, including authorization; explicit
password lookup defaults to 60 seconds. Use `--timeout 2m` to allow longer.
Errors and hints go to stderr; JSON goes to stdout. `--no-prompt-hint` suppresses
the explanatory Keychain hint for password lookup.

## Checks

```sh
make test
make check
```

The standalone Swift test runner needs no XCTest. `make check` builds the app,
verifies its signature/plists and tests help/version and a LaunchServices
version/error round trip. These checks do not scan the radio or access Keychain.
Live scans and permission persistence need separate hardware/signing checks.

To use a separately built bundle, set `MARINUS_APP`. For app round-trip tests,
set `MARINUS_TEST_APP` to its path.

## Shared survey commands and packaging

`scan --json` now emits the shared draft scan envelope and retains all observed
BSSIDs. Use `interfaces --json`, `scan --interface en0 --cached --json` and
`watch --count 10 --json --output captures/walk.jsonl` for the common protocol.
The original summary/array output is available with `scan --legacy`; add
`--bssids` there for the former detailed format. `info` and `password` remain
explicit diagnostic commands.

CoreWLAN exposes no per-observation age, so freshness remains `unknown`, even
after a completed scan. Missing radio values and masked identifiers are null.
See [CLI protocol](../../contracts/cli.md) and [installers](../../docs/packaging.md).
