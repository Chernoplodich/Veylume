#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${VEY_UPDATE_FEED_URL:?Set your actual HTTPS appcast URL}"
: "${VEY_UPDATE_DOWNLOAD_PREFIX:?Set your actual HTTPS download directory URL}"
: "${VEY_SPARKLE_KEY_ACCOUNT:?Set the existing Sparkle signing-key account in Keychain}"
: "${VEY_RELEASE_BUILD_NUMBER:?Set the build number matching the finished DMG}"
archive="${1:-$PWD/artifacts/Veylume.dmg}"
output="$PWD/artifacts/update-staging"
tool="$PWD/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
[[ -x "$tool" && -f "$archive" ]] || { echo 'Build dependencies and a final notarized DMG first' >&2; exit 1; }
feed_name="$(python3 - <<'PY'
import os,pathlib,urllib.parse
for key in ['VEY_UPDATE_FEED_URL','VEY_UPDATE_DOWNLOAD_PREFIX']:
    u=urllib.parse.urlparse(os.environ[key]);assert u.scheme=='https' and u.hostname and not u.username and not u.password and not u.query and not u.fragment
name=pathlib.PurePosixPath(urllib.parse.urlparse(os.environ['VEY_UPDATE_FEED_URL']).path).name
assert name.endswith('.xml') and name not in ['.xml','..xml']
build=os.environ['VEY_RELEASE_BUILD_NUMBER'];assert build.isdigit()
print(name)
PY
)"
xcrun stapler validate "$archive"
mkdir -p "$output"
cp "$archive" "$output/Veylume-$VEY_RELEASE_BUILD_NUMBER.dmg"
# Uses the existing private key in Keychain. No key generation/export, no upload.
"$tool" --account "$VEY_SPARKLE_KEY_ACCOUNT" --download-url-prefix "${VEY_UPDATE_DOWNLOAD_PREFIX%/}/" --maximum-deltas 0 -o "$output/$feed_name" "$output"
echo 'Signed appcast prepared locally. Verify N→N+1 before any publication.'
