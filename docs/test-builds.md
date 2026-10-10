# Download and test a development build

GitHub Actions builds development installers on pull requests, pushes to `main`,
and manual runs of **Marinus checks and test builds**. No signing credentials are
needed. These packages are intended for testing; macOS apps use an ad-hoc
signature without notarization, and Windows/Linux packages are unsigned.

## Download

1. Open [GitHub Actions](https://github.com/kws/marinus/actions/workflows/ci.yml)
   and select a run for the commit you want to test.
2. Check that the relevant platform's job passed. Scroll to **Artifacts** and
   download the `desktop-` or `cli-` artifact for your platform. GitHub requires
   you to [sign in to download Actions artifacts](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts).
3. Unzip the download. It contains the installer, `build-info.json` with the
   exact build commit, `SHA256SUMS`, and this guide as `TESTING.md`.

Artifacts are retained for 30 days. Once this workflow is on the default branch,
use **Run workflow** to rebuild a selected branch. From a terminal:

```sh
gh workflow run ci.yml --repo kws/marinus --ref main
gh run list --repo kws/marinus --workflow ci.yml
gh run download RUN_ID --repo kws/marinus --dir test-build
```

For a pull request, the recorded commit is GitHub's tested merge commit, including
the target branch. All packages currently use version `0.1.0`; use the commit and
run ID to distinguish builds. Checksums detect altered downloads; they do not
replace publisher signing.

| Platform | Desktop artifact | CLI artifact | Install |
| --- | --- | --- | --- |
| macOS Apple Silicon | `desktop-macos-arm64-…` | `cli-macos-arm64-…` | Copy the app from the DMG to Applications; CLI uses a PKG |
| macOS Intel | `desktop-macos-x64-…` | `cli-macos-x64-…` | Copy the app from the DMG to Applications; CLI uses a PKG |
| Windows x64 | `desktop-windows-x64-…` | `cli-windows-x64-…` | Run the setup EXE under your normal user account |
| Debian/Ubuntu x64 | `desktop-linux-x64-…` | `cli-linux-all-…` | `sudo apt install ./PACKAGE.deb` to resolve dependencies |

The macOS builds are separate native binaries, not universal apps. Linux desktop
packages are built on Ubuntu 22.04; other distributions and Windows/Linux ARM64
are not part of this first build matrix.

## Platform permissions

macOS may block an unnotarized development app or package. For a build you trust,
use the per-app **Open Anyway** control in System Settings → Privacy & Security
after attempting to open it, following [Apple's per-app override instructions](https://support.apple.com/en-us/102445).
Keep the scanner's nested `Marinus.app` intact.
Grant Location Services to **Marinus** when requested; this consent belongs to
the scanner, whose identity differs from the desktop GUI. Ad-hoc signatures can
require renewed consent after replacing a build, so these packages cannot prove
that permission retention will work for signed releases.

Windows may show an unknown-publisher or SmartScreen warning. Continue only for
the intended test build. The installers use the current user and scans should
run without elevation. Allow location access when requested; the scanner bundles
its .NET runtime. The desktop installer handles WebView2 when needed.

Linux requires a desktop session, NetworkManager and its normal PolicyKit scan
authorization. Installation needs administrator privileges; run Marinus as your
normal user afterward.

## Test on hardware

CI runs synthetic backend, contract, frontend and Rust checks before retaining
the relevant installers. Hosted runners do not validate real Wi-Fi scans or
normal-user permission prompts. For a downloaded build:

1. Install and launch under your normal user account. In the desktop app, confirm
   the synthetic demo works, then select a real Wi-Fi interface.
2. Try a fresh scan and a cached read. Check filtering, cancellation, a subsequent
   scan, and JSON export. Validate an exported scan with
   `python scripts/check-contracts.py /path/to/export.json` from the source tree.
3. Check denied location/scan permission, then grant access and retry.
4. Reinstall or upgrade from a prior build, then uninstall. Verify captures saved
   outside the application directory remain available.

Report the commit/run ID, installer name, OS version, architecture, Wi-Fi adapter
and observed behavior. Keep identifying captures outside Git unless deliberately
shared for diagnosis.

## Moving to signed releases

Reuse the same packaging scripts in a separate release workflow triggered by a
version tag or a deliberate release dispatch. Keep release credentials in a
protected GitHub environment and out of pull-request jobs. Provision a temporary
macOS Keychain with Developer ID Application/Installer identities and a notarytool
profile; omit `--development` to use the existing signing/notarization path.
On Windows, provision the signing certificate or signing service and use the
existing timestamp/signature verification hooks. Linux distribution via APT will
need a signed repository and Release metadata.

Promote validated artifacts to GitHub Releases after clean installation, upgrade,
permission and removal checks. See [the packaging guide](https://github.com/kws/marinus/blob/main/docs/packaging.md) in the
repository for the current signing variables and platform details. Automatic
updates require their own signed-update design and are a later step.
