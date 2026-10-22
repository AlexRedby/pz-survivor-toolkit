# Project rules

## Purpose

PZ Survivor Toolkit is a quality-of-life project for the user's personal gameplay requests, fixes for bugs they have encountered, and integration of third-party mods they like. The repository includes Toolkit (including Survivor Wishlist), Java patches and supporting tools.

## Fixes

- Find and fix the root cause instead of masking a failure with monkey patches
  or scenario-specific workarounds.
- Check related scenarios for the same cause and fix all affected paths, not
  only the scenario that exposed the bug.
- When replacing an implementation, migrate its consumers and remove the
  superseded code in the same change. If a migration period is necessary, record
  in [TODO.md](TODO.md) what legacy remains, why it is still needed and the
  concrete condition for removing it.

## Checks

Run tests related to the change and affected consumers; do not run the full suite by default. A broader set of fast, inexpensive checks is fine. Run expensive checks, including full builds and native game/integration runs, only when the affected behavior or specific risks require them.

Use the [development guide](docs/DEVELOPMENT.md#checks-and-packaging) for test selection and coverage limits, and the [native runner guide](tests/native_queue/README.md) for in-game scenarios.
