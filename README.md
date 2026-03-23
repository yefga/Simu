# Simu

A concise, interactive CLI tool to list and run iOS Simulators and Android Emulators on macOS.

## Features
- **List Devices**: Beautiful tables showing available simulators/emulators.
- **Run Devices**: Boot devices instantly. Run without arguments for an interactive selection prompt.
- **Auto-Diagnostics**: Detects missing Xcode Command Line Tools or Android SDKs and provides copy-paste installation instructions.

## Installation
Install locally via source:
```bash
git clone https://github.com/example/simu.git
cd simu
bundle install
chmod +x bin/simu
```

## Usage
List commands:
```bash
simu ios list
simu android list
```

Run devices interactively:
```bash
simu ios run
simu android run
```

Run specific devices:
```bash
simu ios run "iPhone 16" iOS26
simu android run Pixel_5
```

## Requirements
- Ruby
- Xcode Command Line Tools (`xcrun`)
- Android Studio (`emulator`)
