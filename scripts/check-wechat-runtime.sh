#!/bin/bash
# Opt-in: creates two unsigned-in WeChat fixtures; leaves fixture data for inspection.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$#" -ne 1 ]; then echo 'Usage: bash scripts/check-wechat-runtime.sh NEW_FIXTURE_DIRECTORY' >&2; exit 2; fi
swift build --disable-sandbox --product CodexMulti
bin_dir="$(swift build --show-bin-path)"
swiftc -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
  scripts/wechat-runtime-fixture.swift -I "$bin_dir/Modules" \
  "$bin_dir"/CodexMultiCore.build/*.swift.o \
  "$bin_dir"/CodexMultiState.build/*.swift.o \
  -o .build/wechat-runtime-fixture
exec .build/wechat-runtime-fixture "$1"
