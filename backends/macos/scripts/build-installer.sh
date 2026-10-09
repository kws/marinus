#!/usr/bin/env bash
set -euo pipefail
backend_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
development=false
case "${1:-}" in
  --development) development=true ;;
  "") ;;
  *) echo "Usage: build-installer.sh [--development]" >&2; exit 2 ;;
esac
if ! $development; then
  : "${SIGN_IDENTITY:?Set a Developer ID Application identity}"
  : "${INSTALLER_SIGN_IDENTITY:?Set a Developer ID Installer identity}"
  : "${NOTARY_PROFILE:?Set a notarytool Keychain profile}"
  [[ "$SIGN_IDENTITY" != "-" ]] || { echo "Public installers require Developer ID signing" >&2; exit 1; }
fi
if $development; then export SIGN_IDENTITY=-; fi
"$backend_root/scripts/build-app.sh"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/payload/Applications" "$temporary/payload/usr/local/bin"
ditto --norsrc --noextattr --noqtn "$backend_root/dist/Marinus.app" "$temporary/payload/Applications/Marinus.app"
ln -s /Applications/Marinus.app/Contents/MacOS/marinus "$temporary/payload/usr/local/bin/marinus"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$backend_root/packaging/Info.plist")"
python3 -c 'import plistlib,sys; plistlib.dump([{"RootRelativeBundlePath":"Applications/Marinus.app","BundleIsRelocatable":False,"BundleIsVersionChecked":True,"BundleHasStrictIdentifier":True,"BundleOverwriteAction":"upgrade"}],open(sys.argv[1],"wb"))' "$temporary/components.plist"
suffix=""
if $development; then suffix="-development"; fi
output="$backend_root/dist/marinus-cli-$version-$(uname -m)$suffix.pkg"
pkg_arguments=(--root "$temporary/payload" --component-plist "$temporary/components.plist" \
  --identifier io.github.kws.marinus.cli --version "$version" --install-location /)
if ! $development; then pkg_arguments+=(--sign "$INSTALLER_SIGN_IDENTITY"); fi
COPYFILE_DISABLE=1 pkgbuild "${pkg_arguments[@]}" "$output"
if ! $development; then
  pkgutil --check-signature "$output"
  xcrun notarytool submit "$output" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json >"$temporary/notary.json"
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); sys.exit(0 if r.get("status")=="Accepted" else "Notarization was not accepted")' "$temporary/notary.json"
  xcrun stapler staple "$output"
  xcrun stapler validate "$output"
fi
echo "Created $output"
