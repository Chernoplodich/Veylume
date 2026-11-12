#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-debug}"
[[ "$mode" == debug || "$mode" == release ]] || { echo 'Usage: build.sh [debug|release]' >&2; exit 2; }
python3 scripts/localizations.py
source scripts/swift-sdk.sh
swift build --cache-path .build/spm-cache "${vey_swift_sdk_args[@]}" -c "$mode" --arch arm64
bin="$(swift build --cache-path .build/spm-cache "${vey_swift_sdk_args[@]}" -c "$mode" --arch arm64 --show-bin-path)"
python3 scripts/check-macos-build.py "$bin/Veylume" "$vey_sdk_version"
python3 scripts/check-macos-build.py "$bin/VeylumeVerify" "$vey_sdk_version"
staging="$PWD/artifacts/.package-$mode-$$"
app="$staging/Veylume.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin/Veylume" "$app/Contents/MacOS/"
cp Configuration/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.Veylume.dev' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VEY_LOCAL_VERSION:-0.1.2}" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VEY_LOCAL_BUILD:-15}" "$app/Contents/Info.plist"
for bundle in "$bin/"*.bundle; do
  [[ ! -e "$bundle" ]] || ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"
done
sparkle="$(find .build/artifacts -type d -path '*/Sparkle.framework' | head -n 1)"
if [[ -n "$sparkle" ]]; then
  ditto "$sparkle" "$app/Contents/Frameworks/Sparkle.framework"
  install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/Veylume" 2>/dev/null || true
fi
for lang in en ru es fr; do
  mkdir -p "$app/Contents/Resources/$lang.lproj"
  cp "Configuration/$lang.lproj/InfoPlist.strings" "$app/Contents/Resources/$lang.lproj/"
done
[[ ! -e Configuration/AppIcon.icns ]] || cp Configuration/AppIcon.icns "$app/Contents/Resources/"
python3 scripts/clean-image-metadata.py "$app/Contents/Resources"
# Strip debug/STABS paths from the distributable before signing. The original
# build products remain available locally for symbolication.
if [[ "$mode" == release ]]; then xcrun strip -S "$app/Contents/MacOS/Veylume"; fi
# Development signing only. Release signing/notarization has a separate script.
python3 scripts/local_signing.py "$app"
final="$PWD/artifacts/Veylume.app"
if [[ -e "$final" ]]; then
  mkdir -p artifacts/previous
  mv "$final" "artifacts/previous/Veylume-$(date -u +%Y%m%dT%H%M%S)-$$.app.backup"
fi
mv "$app" "$final"
rmdir "$staging"
echo "$final"
