fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios generate

```sh
[bundle exec] fastlane ios generate
```

Generate Xcode project via XcodeGen

### ios build_sim

```sh
[bundle exec] fastlane ios build_sim
```

Build app for iOS simulator (Debug)

### ios test_all

```sh
[bundle exec] fastlane ios test_all
```

Run unit tests (macOS core + iOS)

### ios archive

```sh
[bundle exec] fastlane ios archive
```

Archive iOS app (Release)

### ios alpha

```sh
[bundle exec] fastlane ios alpha
```

Build and upload to TestFlight (Release)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build Ad-Hoc beta and host locally

### ios codesign_auto

```sh
[bundle exec] fastlane ios codesign_auto
```

Enable Automatic Signing for project (set DEVELOPMENT_TEAM_ID env var)

### ios bump_patch

```sh
[bundle exec] fastlane ios bump_patch
```

Bump patch version (e.g., 1.0.0 -> 1.0.1) and build number

### ios bump_minor

```sh
[bundle exec] fastlane ios bump_minor
```

Bump minor version (e.g., 1.0.0 -> 1.1.0) and build number

### ios bump_major

```sh
[bundle exec] fastlane ios bump_major
```

Bump major version (e.g., 1.0.0 -> 2.0.0) and build number

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Generate screenshots for App Store submission

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
