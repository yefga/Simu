# Simu

A concise, interactive CLI tool to list and run iOS Simulators and Android Emulators on macOS.

## Features
- **List Devices**: Beautiful tables showing available simulators/emulators.
- **Run Devices**: Boot devices instantly. Run without arguments for an interactive selection prompt.
- **Auto-Diagnostics**: Detects missing Xcode Command Line Tools or Android SDKs and provides copy-paste installation instructions.

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
* `simu android list` - Display Android environments alongside API versions.
* `simu android run` - Open an interactive selection menu.
* `simu android run [NAME]` - Fuzzy-select an explicit named device.
* `simu android launch [PATH]` - Interactively select an emulator, and execute `./gradlew assembleDebug` to natively build and launch the project! Assumes `.` (current directory).tor`)

## Requirements
- Ruby
- Xcode Command Line Tools (`xcrun`)
- Android Studio (`emulator`)
