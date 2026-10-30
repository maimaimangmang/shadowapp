#!/bin/bash
# Opt-in macOS smoke test: opens two temporary, unsigned-in Claude instances.
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:-/Applications/Claude.app}"
swift build --product CodexMulti
bin_dir="$(swift build --show-bin-path)"
swiftc -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
  scripts/claude-runtime-fixture.swift -I "$bin_dir/Modules" \
  "$bin_dir"/CodexMultiCore.build/*.swift.o \
  "$bin_dir"/CodexMultiState.build/*.swift.o \
  -o .build/claude-runtime-fixture
exec .build/claude-runtime-fixture "$app"
