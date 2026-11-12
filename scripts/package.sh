#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:-$PWD/artifacts/Veylume.app}"
output="${2:-$PWD/artifacts/Veylume-local.dmg}"
distribution="${VEY_DISTRIBUTION:-development}"
[[ "$distribution" == development || "$distribution" == release ]] || { echo 'Unknown distribution type' >&2; exit 1; }
[[ -d "$app" ]] || { echo 'Build the app first' >&2; exit 1; }
[[ -x .build/dmg-tools/bin/dmgbuild ]] || { echo 'Install packaging tools: python3 -m venv .build/dmg-tools && .build/dmg-tools/bin/pip install dmgbuild==1.6.7' >&2; exit 1; }
.build/dmg-tools/bin/python scripts/package-image.py "$app" "$output" "$distribution"
hdiutil verify "$output"
python3 scripts/verify-dmg.py "$output" "$app"
shasum -a 256 "$output" > "$output.sha256"
echo "$output"
