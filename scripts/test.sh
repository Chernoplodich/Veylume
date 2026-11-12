#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-sdk.sh
python3 scripts/test-build-metadata.py
python3 scripts/test-local-signing.py
python3 scripts/localizations.py --check
python3 scripts/test-localizations.py
python3 scripts/test-image-metadata.py
# CLT 6.4's Swift Build planner can omit this Apple-provided macro search path
# on an incremental test build. Load the installed plugin explicitly.
runtime_path="$(swift -print-target-info | python3 -c 'import json,sys; print(json.load(sys.stdin)["paths"]["runtimeResourcePath"])')"
testing_plugin="$runtime_path/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$testing_plugin" ]]; then
  swift test --cache-path .build/spm-cache "${vey_swift_sdk_args[@]}" -Xswiftc -load-plugin-library -Xswiftc "$testing_plugin" "$@"
else
  swift test --cache-path .build/spm-cache "${vey_swift_sdk_args[@]}" "$@"
fi
