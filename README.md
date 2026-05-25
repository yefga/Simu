# Simu

A concise, interactive CLI tool to list and run Apple Simulators and Android Emulators.

## Features
- **List Devices**: Tables showing available simulators and emulators.
- **Run Devices**: Boot devices instantly, with interactive selection when no name is supplied.
- **Android Self-Setup**: Install an Android emulator without Android Studio, system Java, or system ADB.
- **Framework Environment**: Run Flutter, React Native, Ionic, or other commands against the Simu-managed Android SDK.

## Installation

The recommended way to install `simu` is via Homebrew:
```bash
brew tap yefga/tap
brew install simu
```

Alternatively, install locally via source:
```bash
git clone https://github.com/yefga/Simu.git
cd Simu
bundle install
```

## Usage
### Apple
* `simu apple list` - Display Apple simulators explicitly.
* `simu apple run` - Activate an interactive selection menu to graphically choose which Simulator to boot!
* `simu apple run [NAME]` - Fuzzy-match a device explicitly (E.g. `simu apple run iphone15` to boot into `iPhone 15 Simulator`).
* `simu apple launch [PATH]` - Interactively select a simulator and compile an `.xcworkspace`, `.xcodeproj`, or `.app` directly onto it! Assumes `.` (current directory).
* `simu apple doctor` - Check for iOS CLI dependencies natively on your Mac.

### Android
Start by checking your environment:
```bash
simu android doctor
simu android setup
simu android run
```

`setup` installs a private current-LTS Eclipse Temurin 25 Java runtime used only for provisioning, Android command-line tools, `adb`, the emulator, and your selected virtual device under `~/.simu/android`. Archive downloads display a rotating progress indicator and percentage, while Android SDK Manager displays its package download progress. It asks you to accept Android SDK licenses and choose a compatible system image and phone profile. Existing usable Android SDK installations are reused first.

* `simu android doctor` - Inspect host compatibility and Android setup readiness without installing anything.
* `simu android setup` - Provision a private SDK/emulator installation and create an Android virtual device.
* `simu android list` - Display Android emulators alongside API versions.
* `simu android run [NAME]` - Boot a selected or named Android emulator.
* `simu android launch path/to/app.apk` - Install and open an already built APK on an emulator.
* `simu android launch [PROJECT_PATH]` - Best-effort Gradle Android project build followed by installation.
* `simu android exec -- flutter run` - Run an installed framework CLI with Simu's Android SDK/ADB environment.

For example, framework-managed builds can target the Simu emulator without installing Android Studio:
```bash
simu android run
simu android exec -- flutter run
# or: simu android exec -- npx react-native run-android
# or: simu android exec -- ionic cap run android
```

## Requirements
- Ruby
- Apple commands: macOS with Xcode Command Line Tools (`xcrun`)
- Android commands: macOS on Apple silicon or Intel, or Linux `x86_64` with virtualization support

Android Studio is not required for Android emulator or APK workflows. Simu does not install framework CLIs or source-project build requirements such as Node.js, Flutter, Gradle plugins, a project JDK, or an NDK required by native dependencies.
