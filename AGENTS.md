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

## macOS native-test launch

Use the common runner's default `auto` desktop policy; do not select a strategy based on screen lock or ask the user to wake the screen. Run the GUI command outside the sandbox in the logged-in macOS session. An unavailable CoreGraphics probe means GUI access is unknown, not that the display needs waking. Automatic routing isolates owned windows through AeroSpace, permits the guarded fallback only with confirmed physical-display sleep, and recovers discoverable fallback windows into the test workspace. Explicit `--desktop-mode aerospace` requires placement; legacy `current` retains the guarded automatic policy. Never change the user's display state, workspace or focus to enable a test. Prepare a fresh snapshot when the runner requests one; do not bypass its input or PID/window guards. See [desktop launch](tests/native_queue/README.md#desktop-launch) for the command and validation limits.

## Process friction

Record process friction encountered during the current task in the root `TODO.md` as soon as it appears. This includes tool failures, unexpected errors in logs, awkward or slow setup, repetitive manual work, missing diagnostics, and a need for supporting scripts or tools outside the task's scope.

Before adding an item, check `TODO.md` for the same underlying problem, including differently worded entries. Add useful new context to an existing item instead of creating a duplicate. Keep the item concise and actionable: describe the observed problem, its impact, available evidence (such as a command, error, log or file path), and the next step or completion condition. Distinguish observations from suspected causes; a full investigation is not required before recording the issue.

After recording it, continue the current task. A TODO entry does not expand the task's scope or authorize unrelated tooling work. If the problem blocks progress, report the blocker and handle what is necessary to proceed within the existing authorization.
