#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
mkdir -p .build/tests
sources=()
for source in Sources/MarinusCLI/*.swift; do
  if [[ "$source" != */MarinusMain.swift ]]; then sources+=("$source"); fi
done
"${SWIFTC:-swiftc}" -parse-as-library -Onone \
  -module-cache-path "$repo_root/.build/test-module-cache" \
  -target "${SWIFT_TARGET:-$(uname -m)-apple-macos13.0}" \
  -framework CoreWLAN -framework CoreLocation -framework Security \
  "${sources[@]}" Tests/MarinusCLITests/*.swift Tests/TestRunner.swift \
  -o .build/tests/marinus-tests
.build/tests/marinus-tests
