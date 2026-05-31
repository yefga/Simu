# Development Guide

## Local Setup

Requirements:

- Ruby and Bundler.
- Xcode Command Line Tools for exercising Apple commands on macOS.
- Network access and several GB of free space only when testing `simu android setup`.

Install dependencies and run the working tree version:

```bash
bundle install
ruby -Ilib bin/simu version
ruby -Ilib bin/simu android help
```

Using `ruby -Ilib bin/simu` is important while developing: a Homebrew-installed `simu` binary may still point at a released build.

## Project Layout

- `lib/simu/cli.rb` defines top-level commands and combined device listing.
- `lib/simu/apple.rb` owns Apple simulator discovery, boot, build, and deploy behavior.
- `lib/simu/android.rb` owns Android commands, emulator booting, APK installation, project launch, and framework command execution.
- `lib/simu/android_toolchain.rb` resolves existing versus Simu-managed Android tooling and supplies child-process environments.
- `lib/simu/android_installer.rb` provisions the private Java runtime, SDK packages, system image, and AVD.
- `spec/` contains RSpec coverage for toolchain selection, installer behavior, and CLI command routing.

## Android Design Boundary

Managed setup writes only beneath `SIMU_HOME` or its default, `~/.simu/android`.

Runtime commands inject Android SDK and ADB environment variables for child processes and remove an inherited `JAVA_HOME` only when it points to a missing Java executable. The private Temurin JRE is injected only for Android provisioning commands; application/framework builds must select their own compatible Java and any required NDK/CMake setup.

`simu android launch` without a path boots an emulator only. With an explicit APK path it installs and launches that APK. With an explicit directory it attempts a Gradle debug build and deploy.

## Verification

Run the automated suite:

```bash
rspec -Ilib spec
```

For Android feature work, check the lint-clean Android surface and specs:

```bash
XDG_CACHE_HOME=/private/tmp/simu-rubocop-cache \
  rubocop --only Lint,Layout/LineLength \
  lib/simu/android.rb lib/simu/android_installer.rb lib/simu/android_toolchain.rb spec
```

Validate a Homebrew formula when modifying it:

```bash
HOMEBREW_CACHE=/private/tmp/simu-homebrew-cache brew style Formula/simu.rb
```

Full Android setup and emulator boot are interactive/manual checks because they download SDK artifacts, require license acceptance, and depend on host virtualization.

## Release And Homebrew Tap

For a new release:

1. Update `lib/simu/version.rb` and `simu.gemspec`.
2. Run the test suite and build the gem locally with `gem build simu.gemspec`.
3. Commit the release version and create the corresponding `vX.Y.Z` tag.
4. Push `main` and the tag, then compute the SHA-256 of the published GitHub tag archive.
5. Update `Formula/simu.rb` and the external `homebrew-tap/Formula/simu.rb` URL, checksum, gem filename, and version assertion.
6. Validate the formula with `brew style`, then commit and push the tap update branch.

Do not move an already published tag to add fixes; publish a patch version instead.
