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

### ios test

```sh
[bundle exec] fastlane ios test
```

Run the UsageCore test suite

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build & upload the iOS app to TestFlight

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload iOS metadata + screenshots (no binary) for review prep

### ios release

```sh
[bundle exec] fastlane ios release
```

Full iOS App Store release (build + upload + metadata)

----


## Mac

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Build & upload the Mac app to TestFlight / App Store Connect

### mac metadata

```sh
[bundle exec] fastlane mac metadata
```

Upload Mac metadata + screenshots (no binary)

### mac release

```sh
[bundle exec] fastlane mac release
```

Full Mac App Store release

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
