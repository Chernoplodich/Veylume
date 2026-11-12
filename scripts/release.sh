#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${VEY_DEVELOPER_IDENTITY:?Set the Developer ID Application identity in your environment}"
: "${VEY_TEAM_ID:?Set your actual Team ID}"
: "${VEY_RELEASE_BUNDLE_ID:?Set your stable release Bundle ID}"
: "${VEY_NOTARY_PROFILE:?Set an existing notarytool Keychain profile name}"
: "${VEY_UPDATE_FEED_URL:?Set your real HTTPS appcast URL}"
: "${VEY_UPDATE_PUBLIC_ED_KEY:?Set the public Sparkle EdDSA key}"
: "${VEY_RELEASE_VERSION:?Set the actual release version}"
: "${VEY_RELEASE_BUILD_NUMBER:?Set an incrementing build number}"
xcodebuild -version
python3 scripts/localizations.py
xcodebuild -project Veylume.xcodeproj -scheme Veylume -configuration Release -destination 'generic/platform=macOS' -archivePath "$PWD/artifacts/Veylume.xcarchive" CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER="$VEY_RELEASE_BUNDLE_ID" MARKETING_VERSION="$VEY_RELEASE_VERSION" CURRENT_PROJECT_VERSION="$VEY_RELEASE_BUILD_NUMBER" archive
app="$PWD/artifacts/Veylume.xcarchive/Products/Applications/Veylume.app"
source scripts/swift-sdk.sh
python3 scripts/check-macos-build.py "$app/Contents/MacOS/Veylume" "$vey_sdk_version"
xcrun strip -S "$app/Contents/MacOS/Veylume"
python3 scripts/clean-image-metadata.py "$app/Contents/Resources"
export VEY_RELEASE_APP="$app"
python3 - <<'PY'
import base64,os,pathlib,plistlib,urllib.parse
p=pathlib.Path(os.environ['VEY_RELEASE_APP'])/'Contents/Info.plist';d=plistlib.loads(p.read_bytes())
feed=os.environ['VEY_UPDATE_FEED_URL'];u=urllib.parse.urlparse(feed)
assert u.scheme=='https' and u.hostname and not u.username and not u.password and not u.fragment
assert len(base64.b64decode(os.environ['VEY_UPDATE_PUBLIC_ED_KEY'],validate=True))==32
d.update(CFBundleIdentifier=os.environ['VEY_RELEASE_BUNDLE_ID'],SUFeedURL=feed,SUPublicEDKey=os.environ['VEY_UPDATE_PUBLIC_ED_KEY'],SUEnableAutomaticChecks=False,SUAutomaticallyUpdate=False,SUEnableSystemProfiling=False,SURequireSignedFeed=True,SUVerifyUpdateBeforeExtraction=True)
p.write_bytes(plistlib.dumps(d))
PY
python3 scripts/sign-nested.py "$app"
codesign -dv "$app" 2>&1 | rg "TeamIdentifier=$VEY_TEAM_ID"
ditto -c -k --keepParent "$app" artifacts/Veylume-notary.zip
xcrun notarytool submit artifacts/Veylume-notary.zip --keychain-profile "$VEY_NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
VEY_DISTRIBUTION=release bash scripts/package.sh "$app" "$PWD/artifacts/Veylume.dmg"
codesign --sign "$VEY_DEVELOPER_IDENTITY" --timestamp artifacts/Veylume.dmg
xcrun notarytool submit artifacts/Veylume.dmg --keychain-profile "$VEY_NOTARY_PROFILE" --wait
xcrun stapler staple artifacts/Veylume.dmg
xcrun stapler validate artifacts/Veylume.dmg
spctl --assess --type execute --verbose=2 "$app"
spctl --assess --type open --context context:primary-signature --verbose=2 artifacts/Veylume.dmg
shasum -a 256 artifacts/Veylume.dmg > artifacts/Veylume.dmg.sha256
echo 'Prepared and verified locally. No public upload was performed.'
