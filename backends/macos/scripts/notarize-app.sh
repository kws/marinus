#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to a Developer ID Application identity}"
if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "Notarization requires a Developer ID Application identity." >&2
  exit 1
fi
./scripts/build-app.sh
bundle="$repo_root/dist/Marinus.app"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
ditto -c -k --keepParent "$bundle" "$temporary/Marinus.app.zip"
xcrun notarytool submit "$temporary/Marinus.app.zip" \
  --keychain-profile "${NOTARY_PROFILE:-marinus-notary}" --wait
xcrun stapler staple "$bundle"
xcrun stapler validate "$bundle"
spctl -a -t exec "$bundle"
ditto -c -k --keepParent "$bundle" "$repo_root/dist/Marinus.app.zip"
echo "Created dist/Marinus.app.zip"
