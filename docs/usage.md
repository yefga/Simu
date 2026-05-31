# Usage Guide

## Commands

```bash
simu list
simu version
simu apple help
simu android help
```

`simu list` displays available devices across supported platforms. Apple commands are macOS-only; Android commands also support Linux `x86_64`.

## Apple Simulators

Apple commands use the simulator tools installed with Xcode Command Line Tools.

```bash
simu apple doctor
simu apple list
simu apple run
simu apple run iphone15
simu apple launch path/to/App.app
simu apple launch path/to/ios-project
```

`apple run` boots a selected simulator. `apple launch` installs an `.app` or builds and deploys an Xcode project/workspace.

## Android Setup

Check whether an existing Android SDK is usable:

```bash
simu android doctor
```

If no usable emulator setup is found, install a private one:

```bash
simu android setup
```

Setup:

- Stores managed files under `~/.simu/android`.
- Downloads a private Eclipse Temurin 25 JRE for provisioning commands only.
- Downloads Android SDK command-line tools with checksum verification.
- Installs the emulator, ADB, APK inspection build tools, and a selected system image.
- Prompts for Android SDK license acceptance and for an emulator image/device selection.
- Shows download progress for Simu-managed archives and preserves Android SDK Manager package progress.

When an existing functional Android SDK is available, Simu uses it first and offers managed setup only when requested.

## Launch An Emulator

List configured devices and start one:

```bash
simu android list
simu android launch
```

`simu android launch` is an emulator-only operation: it selects an AVD and boots it without looking for `gradlew`, compiling an app, or installing an APK.

To boot a known emulator directly:

```bash
simu android run simu_pixel_9a_api_36
```

## Install Or Build An App

Install and open an already-built APK:

```bash
simu android launch path/to/app.apk
```

Build a direct Android Gradle project and deploy its debug APK:

```bash
simu android launch path/to/android-project
```

Project launch requires an executable `gradlew` in the supplied directory. Simu supplies the Android SDK/ADB environment, but build-specific Java, NDK, CMake, Gradle plugin, or dependency requirements belong to the project.

## Flutter And React Native

First boot an emulator:

```bash
simu android launch
```

Then execute your installed framework tooling with Simu's managed Android SDK and ADB paths:

```bash
simu android exec -- flutter run
simu android exec -- npx react-native run-android
simu android exec -- ionic cap run android
```

Simu does not install the framework CLI, Node.js, Dart/Flutter, or project dependencies. It makes its emulator and Android device tooling visible to those commands.
Framework Android builds still require a JDK compatible with the project's Gradle and Android Gradle Plugin versions. Simu ignores an inherited `JAVA_HOME` when it points to a missing Java executable, allowing the framework command to find an available Java runtime from `PATH`.

## Troubleshooting

Run diagnostics:

```bash
simu android doctor
```

If an upgraded command still prints an Android Studio installation prompt, check which executable is in use and upgrade the Homebrew installation:

```bash
command -v simu
simu version
brew update
brew upgrade simu
```

If Gradle reports that `JAVA_HOME` is an invalid directory, confirm that the configured JDK still exists:

```bash
test -x "$JAVA_HOME/bin/java" && "$JAVA_HOME/bin/java" -version
java -version
```

For a broken shell setting, remove or update `JAVA_HOME` and rerun the framework command with a project-compatible JDK installed:

```bash
unset JAVA_HOME
simu android exec -- npx react-native run-android
```

Managed Android files are located under `~/.simu/android`; no shell profile exports are required for Simu commands.
