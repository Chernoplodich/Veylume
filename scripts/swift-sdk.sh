# Sourced by local SwiftPM scripts. Keep minimum OS separate from linked SDK:
# Swift Build can otherwise stamp sdk=14.0 and select legacy native controls.
vey_sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
vey_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
vey_swift_sdk_args=(--sdk "$vey_sdk_path" -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$vey_sdk_version")
