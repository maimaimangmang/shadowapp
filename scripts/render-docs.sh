#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift_options=(--disable-sandbox --cache-path .build/package-cache --config-path .build/config --security-path .build/security)
xcrun swift build "${swift_options[@]}" --product CodexMulti
bin_dir="$(xcrun swift build "${swift_options[@]}" --show-bin-path)"
ui_sources=()
for source in Sources/CodexMulti/*.swift; do
    [[ "$source" == */CodexMultiApp.swift ]] || ui_sources+=("$source")
done
xcrun swiftc -parse-as-library -I "$bin_dir/Modules" \
    "$bin_dir"/CodexMultiCore.build/*.o "$bin_dir"/CodexMultiState.build/*.o \
    "${ui_sources[@]}" scripts/render-docs.swift -o .build/render-docs
.build/render-docs "$PWD/docs/images/zh" -AppleLanguages '(zh-Hans)'
.build/render-docs "$PWD/docs/images/en" -AppleLanguages '(en)'
