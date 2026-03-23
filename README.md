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
List commands:
```bash
simu apple list
simu android list
```

Run devices interactively:
```bash
simu apple run
simu android run
```

Run specific devices:
```bash
simu apple run "iPhone 16" iOS26
simu android run Pixel_5
```

Validate infrastructure health:
```bash
simu apple doctor
simu android doctor
```

## Requirements
- Ruby
- Xcode Command Line Tools (`xcrun`)
- Android Studio (`emulator`)
