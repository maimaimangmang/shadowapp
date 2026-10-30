#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

arch="${1:-$(uname -m)}"
case "$arch" in arm64|x86_64) ;; *) echo "Usage: bash scripts/package-dmg.sh [arm64|x86_64]" >&2; exit 2 ;; esac
output_dir="${SHADOWAPP_OUTPUT_DIR:-$PWD/dist}"
output_dir="$(cd "$output_dir" && pwd)"
app="$output_dir/$arch/ShadowApp.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$version" == "$app_version" ]] || { echo "Build the current app version before packaging." >&2; exit 1; }
[[ "$(lipo -archs "$app/Contents/MacOS/CodexMulti")" == "$arch" ]] || { echo "App architecture does not match." >&2; exit 1; }
codesign --verify --strict "$app"

mkdir -p .build
stage="$(mktemp -d "$PWD/.build/dmg-$arch.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/ShadowApp.app"
ln -s /Applications "$stage/Applications"
image="$output_dir/ShadowApp-$version-$arch.dmg"
hdiutil create -volname "ShadowApp $version" -srcfolder "$stage" -format UDZO -ov "$image"
hdiutil verify "$image"
(cd "$output_dir" && shasum -a 256 "$(basename "$image")" > "$(basename "$image").sha256")
printf 'Disk image: %s\n' "$image"
