#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
swift_bin="${SWIFT:-swift}"
identity="${SIGN_IDENTITY:--}"

"$swift_bin" build --configuration release
bin_path="$("$swift_bin" build --configuration release --show-bin-path)"
bundle="$repo_root/dist/Marinus.app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
project_root="$(cd "$repo_root/../.." && pwd)"
cp "$project_root/LICENSE" "$bundle/Contents/Resources/LICENSE"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp -R "$project_root/licenses" "$bundle/Contents/Resources/licenses"
cp packaging/Info.plist "$bundle/Contents/Info.plist"
cp "$bin_path/marinus" "$bundle/Contents/MacOS/marinus"

codesign --force --sign "$identity" --options runtime \
  --entitlements packaging/entitlements.plist "$bundle"
codesign --verify --deep --strict "$bundle"
ln -sfn Marinus.app/Contents/MacOS/marinus "$repo_root/dist/marinus"
echo "Built $repo_root/dist/marinus"
if [ "$identity" = "-" ]; then
  echo "Ad-hoc signed development build. Use a stable signing identity for persistent Location Services authorization."
fi
