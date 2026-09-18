#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

arch="${1:-$(uname -m)}"
case "$arch" in arm64|x86_64) ;; *) echo "Usage: bash scripts/build.sh [arm64|x86_64]" >&2; exit 2 ;; esac
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift_options=(--disable-sandbox --cache-path .build/package-cache --config-path .build/config --security-path .build/security)

xcrun swift build "${swift_options[@]}" -c release --arch "$arch" --product CodexMulti
bin_dir="$(xcrun swift build "${swift_options[@]}" -c release --arch "$arch" --show-bin-path)"
app="$PWD/dist/$arch/Codex Multi.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/CodexMulti" "$app/Contents/MacOS/CodexMulti"
xcrun strip -S "$app/Contents/MacOS/CodexMulti"
cp Resources/Info.plist "$app/Contents/Info.plist"
xcrun swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
if [ -n "${CODEX_MULTI_SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$CODEX_MULTI_SIGN_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
archive="$PWD/dist/Codex-Multi-$version-$arch.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
(cd dist && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
printf 'Built app: %s\nRelease archive: %s\n' "$app" "$archive"
