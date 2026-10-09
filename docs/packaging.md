# Installers and signing

The initial pipeline supports a macOS CLI PKG and desktop DMG, Windows CLI and
desktop NSIS setup EXEs, and Linux CLI/desktop DEBs. These are development
packaging foundations. Signed distribution, installed permissions, upgrades and
uninstall behavior need verification before a public release. GitHub Actions
retains development installers for testing for 30 days; see
[download and testing instructions](test-builds.md). GitHub Releases are not
published automatically.

## macOS

```sh
backends/macos/scripts/build-installer.sh --development
cd desktop
npm ci
npm run release -- --development
```

The CLI package installs `Marinus.app` under `/Applications` and a CLI symlink at
`/usr/local/bin/marinus`. The app is non-relocatable in the package. The desktop
DMG contains `Marinus Desktop.app` and an Applications shortcut. Both retain the
Swift scanner's original privacy identity. Installer privileges do not elevate
the scanner's runtime. Build on each supported architecture; these scripts do
not produce universal binaries.

Signed builds omit `--development` and require `SIGN_IDENTITY` (Developer ID
Application), `NOTARY_PROFILE` (existing notarytool Keychain profile), and, for
the CLI package, `INSTALLER_SIGN_IDENTITY` (Developer ID Installer). The scripts
verify signatures, submit the finished PKG/DMG, require an Accepted response and
staple/validate its ticket. No credentials are stored in the repository.
The desktop pipeline notarizes/staples the scanner before sealing the GUI app,
then notarizes/staples the app and its finished disk image for offline checks.
See [Apple Developer ID](https://developer.apple.com/developer-id/) and
[Tauri signing](https://v2.tauri.app/distribute/sign/macos/).

For CLI removal, remove the installed app and its symlink, then forget the
`io.github.kws.marinus.cli` receipt. Check the symlink target first; survey captures
are separate and should be retained. The desktop application can be removed
through Finder. Test replacing an older signed build without resetting consent.

## Windows

The CLI installer requires the .NET 10 SDK and NSIS 3 (`makensis` in PATH):

```powershell
backends/windows/scripts/build-installer.ps1 -Development
```

It installs for the current user under `%LOCALAPPDATA%\MarinusCLI` and registers
an uninstaller in Settings. Invoke `marinus.exe` in that directory, or explicitly
add it to your user PATH. Its uninstall manifest removes only bundled files,
preserving other files in the installation directory. It uses the same install
path/registration for upgrades; test upgrading from the preceding package.

The GUI is built with `npm run release -- --development` in `desktop/`; Tauri
builds its current-user NSIS installer. Supported targets are native x64/ARM64;
cross-architecture packaging is not implemented in the desktop preparation step.
The x64 development GUI was installed and tested without elevation on Windows 11
with an Intel AX201 on 2026-10-09. Live/cache reads, filtering, cancellation and
native JSON export passed. A same-version reinstall retained captures outside the
installation directory. See the [desktop validation notes](../desktop/README.md#windows-hardware-validation).

For signed builds, omit the development switch and set `WINDOWS_SIGN_THUMBPRINT`
to an installed certificate and `WINDOWS_TIMESTAMP_URL` to its RFC 3161 service.
The Windows SDK's `signtool` must be in PATH. CLI builds also accept `-SignTool`
and `-MakeNSIS` paths. The scanner and installers are signed and timestamped;
NSIS/Tauri signing covers the embedded uninstaller. See
[SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool).
Verify normal-user location consent from the installed scanner, alongside upgrade
and removal. A signature does not establish SmartScreen reputation.

## Linux

```sh
python3 scripts/package-linux.py
# Portable staging check without dpkg:
python3 scripts/package-linux.py --stage-only
```

The CLI package installs `/usr/bin/marinus`, its collector under `/usr/lib/marinus`,
and notices under `/usr/share/doc/marinus`. It declares Python, D-Bus and
NetworkManager dependencies. Desktop builds produce a DEB with those dependencies
plus Tauri's system webview requirements. Both use existing NetworkManager and
PolicyKit policy; no policy override, sudoers change or privileged collector is
installed. A desktop session and an SSH session can have different authorization.

DEB builds are unsigned local artifacts. Authenticating a future APT repository
requires signed Release metadata and a project signing key; no repository or
trust key is installed by these scripts. RPM packaging/signing is deferred.
Automatic updates and update-signature verification are also deferred.

## Before release

Validate clean installation, normal-user scans and permission-denial handling,
an upgrade from the prior package, and uninstall while retaining captures on each
target platform. Review `notices/desktop-dependencies.json` and bundled licenses,
including packages that did not supply a full license text. Confirm architecture,
minimum OS support, stable publisher/app identity, signatures and notarization
from the actual installed artifacts. Synthetic CI covers behavior/builds and
retains development packages; it cannot replace these installed checks.
