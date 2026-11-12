#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/downloads .build/spm-cache/artifacts
fetch() {
  local artifact_url="$1" expected_sha="$2" artifact_file=".build/downloads/$3"
  if [[ ! -f "$artifact_file" ]] || [[ "$(shasum -a 256 "$artifact_file" | cut -d ' ' -f 1)" != "$expected_sha" ]]; then
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 20 --max-time 600 --output "$artifact_file" "$artifact_url"
  fi
  [[ "$(shasum -a 256 "$artifact_file" | cut -d ' ' -f 1)" == "$expected_sha" ]] || { echo 'Binary artifact integrity failure' >&2; exit 1; }
  local artifact_key
  artifact_key="$(echo "$artifact_url" | tr -c 'a-zA-Z0-9_' '_' | sed 's/_$//')"
  cp "$artifact_file" ".build/spm-cache/artifacts/$artifact_key"
}
# SwiftPM revalidates these hashes itself; this is its documented-source cache
# layout, not a replacement for code signing, HTTPS, or artifact verification.
fetch 'https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip' '4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a' 'Sparkle.zip'
fetch 'https://github.com/FluidInference/text-processing-rs/releases/download/v0.3.1/NemoTextProcessing.xcframework.zip' '5fa8c10d4ec26c1bb2413125f351a7222a4c68a23b74476680fbada7e26fc6aa' 'NemoTextProcessing.zip'
swift package --cache-path .build/spm-cache resolve
