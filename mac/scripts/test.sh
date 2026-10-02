#!/usr/bin/env bash
# Runs the NextletCore unit tests. With only the Command Line Tools installed,
# SwiftPM doesn't find the swift-testing macro plugin on its own, so pass it in.
set -euo pipefail
cd "$(dirname "$0")/.."

args=()
plugin="$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$plugin" ]]; then
  args+=(-Xswiftc -load-plugin-library -Xswiftc "$plugin")
fi

swift test "${args[@]}" "$@"
