# Build from source

**English** · [Русский](ru/building.md) · [Back to Veylume](../README.md)

## Toolchain

Use an Apple silicon Mac with Swift 6.2 or newer and the macOS SDK. Install Xcode or the Command Line Tools. Development has been checked with Swift 6.4 and SDK 27; a full Xcode archive and every supported older macOS version have not been tested.

```sh
git clone https://github.com/Chernoplodich/Veylume.git
cd Veylume
bash scripts/bootstrap-dependencies.sh
bash scripts/test.sh
bash scripts/build.sh release
```

The app is written to `artifacts/Veylume.app`. End users do not need Swift, Python, Homebrew, or a development environment.

To install your build, quit any running Veylume, then run:

```sh
bash scripts/install-local.sh
```

The default destination is `~/Applications/Veylume.app`. A new local signature may need new macOS permissions.

## Dependencies and models

`Package.resolved` pins the Swift dependencies. Bootstrap downloads fixed binary artifacts and checks their SHA-256 digests. Model manifests pin their revisions and artifact hashes. Model weights, personal recordings, local databases, signing profiles, and private keys are not part of the source repository.

The normal first-launch flow installs Parakeet V3. Do not copy your own Application Support folder into a release.

## Signing and packaging

Without a local signing profile, development builds use ad-hoc signing. `scripts/setup-local-signing.py` can set up a persistent personal development identity for your own Mac. It does not create an Apple Developer ID or notarize an app. Never commit its local profile or private key.

For a local disk image:

```sh
python3 -m venv .build/dmg-tools
.build/dmg-tools/bin/pip install dmgbuild==1.6.7
bash scripts/package.sh
```

`package.sh` mounts the result read-only and verifies the packaged signature and bundle contents. `release.sh` is the separate Developer ID and notarization path; it requires the maintainer's real credentials and update configuration and never uploads a public release by itself.

See [Contributing](../CONTRIBUTING.md) for the recording and insertion invariants.
