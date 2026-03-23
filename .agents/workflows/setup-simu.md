---
description: How to setup and run the simu CLI locally for development
---

# Simu Setup Workflow

To test the `simu` CLI from source during development:

1. Ensure you have Ruby installed.
2. Run `bundle install` internally in the project root to install all dependencies (`thor`, `tty-prompt`, `terminal-table`, `pastel`).
// turbo
3. Grant execution rights to the entrypoint: `chmod +x bin/simu`
4. Run the tool locally: `./bin/simu help`

Test iOS integration:
- `./bin/simu ios list`

Test Android integration:
- `./bin/simu android list`
