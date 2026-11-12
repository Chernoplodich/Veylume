#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/artifacts/Veylume.app"
destination="${1:-$HOME/Applications/Veylume.app}"
[[ -d "$app" ]] || { echo 'Run scripts/build.sh first' >&2; exit 1; }
if pgrep -x Veylume >/dev/null 2>&1; then
  echo 'Quit Veylume before installing. Replacing a running ad-hoc copy makes permission checks ambiguous.' >&2
  exit 1
fi
[[ "$destination" == */Veylume.app ]] || { echo 'Destination must be Veylume.app' >&2; exit 1; }
if [[ -d "$destination" ]]; then
  identity="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")"
  [[ "$identity" == local.Veylume.dev ]] || { echo 'A different installed identity exists; choose another destination' >&2; exit 1; }
  echo 'The installed development copy will be archived before replacement.'
fi
mkdir -p "$(dirname "$destination")"
temporary="$(dirname "$destination")/.Veylume-install-$$.app"
ditto "$app" "$temporary"
codesign --verify --deep --strict "$temporary"
if [[ -d "$destination" ]]; then
  mkdir -p "$PWD/artifacts/installed-backups"
  mv "$destination" "$PWD/artifacts/installed-backups/Veylume-$(date -u +%Y%m%dT%H%M%S)-$$.app.backup"
fi
mv "$temporary" "$destination"
if [[ "${VEY_OPEN_AFTER_INSTALL:-1}" == 1 ]]; then open "$destination"; fi
