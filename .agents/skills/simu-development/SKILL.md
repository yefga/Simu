---
name: simu-development
description: Strict guidelines for coding the simu CLI
---

# Simu CLI Code Guidelines

When implementing or fixing features in the `simu` repository, follow these rules:

1. **Routing via Thor**: All CLI commands must be implemented using `Thor` inside `lib/simu/cli.rb` or its submodules.
2. **Strict UI Separation**: Do not output raw text (e.g., `puts`, `print`) in the logic files. Delegate all output to the `Simu::UI` module (`lib/simu/ui.rb`).
3. **Use TTY Toolkit**:
   - For lists/grids: Use `terminal-table`.
   - For interactive prompts (e.g., "Which emulator to run?"): Use `tty-prompt`.
   - For coloring text: Use `pastel`, instantiated in `Simu::UI`.
4. **Resilience**: Never assume `xcrun` or `emulator` paths are correct. Use helper methods in `Simu::Setup` to verify existence before execution, and gracefully prompt the user to install them if missing.
5. **No Monkey Patching**: Do not patch standard Ruby classes.
6. **Code Style**: Use standard Ruby conventions (2 spaces for indentation, frozen_string_literal comments).
