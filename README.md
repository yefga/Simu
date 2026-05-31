# Simu

Simu is an interactive CLI for listing and launching Apple simulators and Android emulators. It can provision a private Android emulator environment without requiring Android Studio.

## Highlights

- List and launch Apple simulators and Android emulators from one CLI.
- Set up an Android emulator with managed SDK tools, ADB, and a private Java runtime.
- Run an emulator without building an app, or install and launch an existing APK.
- Expose the managed Android SDK to Flutter, React Native, Ionic, and other framework commands.

## Installation

Install through Homebrew:

```bash
brew tap yefga/tap
brew install simu
```

Upgrade an existing installation:

```bash
brew update
brew upgrade simu
simu version
```

Install from source for development:

```bash
git clone https://github.com/yefga/Simu.git
cd Simu
bundle install
ruby -Ilib bin/simu version
```

## Quick Start

Apple simulators on macOS:

```bash
simu apple list
simu apple run
```

Android emulator setup and launch:

```bash
simu android doctor
simu android setup
simu android launch
```

`simu android launch` selects and boots an emulator only. Pass an APK or Android project path when you also want Simu to deploy an app.

## Documentation

- [Usage guide](docs/usage.md): Android setup, device commands, APK deployment, and framework workflows.
- [Development guide](docs/development.md): local setup, architecture, tests, and release/formula maintenance.

## Requirements

- Ruby.
- Apple commands require macOS with Xcode Command Line Tools.
- Android setup supports macOS on Apple silicon or Intel, and Linux `x86_64` with virtualization support.

Android Studio is not required for Android emulator or APK workflows. Simu does not install Flutter, Node.js, framework dependencies, or project-specific Java, Gradle, NDK, or CMake requirements.
