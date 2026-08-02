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

### ios build

```sh
[bundle exec] fastlane ios build
```

Regenerate the Xcode project and build a signed release archive

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Upload a new build to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Upload build + metadata to App Store Connect for review submission

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Replace the App Store screenshots only

### ios privacy

```sh
[bundle exec] fastlane ios privacy
```

Declare the app privacy nutrition label (data not collected)

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Push metadata (description, keywords, URLs) without a new build

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
