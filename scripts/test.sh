#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
TEST_ARGS=(--disable-xctest)
TOOLCHAIN_BIN="$(dirname "$(xcrun --find swiftc)")"
TESTING_PLUGIN="$TOOLCHAIN_BIN/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$TESTING_PLUGIN" ]]; then
    TEST_ARGS+=(-Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN")
fi
swift test "${TEST_ARGS[@]}"
