#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
model_id="${1:-parakeet-v3}"
model_directory="${2:?Pass a complete installed model directory}"
mkdir -p artifacts/fixtures artifacts/evidence
source scripts/swift-sdk.sh
swift build --cache-path .build/spm-cache "${vey_swift_sdk_args[@]}" --product VeylumeVerify
verify_bin="$(swift build --cache-path .build/spm-cache "${vey_swift_sdk_args[@]}" --show-bin-path)/VeylumeVerify"
python3 scripts/check-macos-build.py "$verify_bin" "$vey_sdk_version"
say -v Samantha -f VeylumeTests/Fixtures/en.txt -o artifacts/fixtures/en.aiff
say -v Milena -f VeylumeTests/Fixtures/ru.txt -o artifacts/fixtures/ru.aiff
for lang in en ru; do
  # Network is denied only to this verification process; system connectivity,
  # TCC and the user's application protections are not changed.
  /usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)' "$verify_bin" asr "$model_id" "$model_directory" "artifacts/fixtures/$lang.aiff" "VeylumeTests/Fixtures/$lang.txt" "$lang" > "artifacts/evidence/$model_id-$lang.json"
done
