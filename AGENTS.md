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

Record process friction encountered during the current task as soon as it appears, choosing the TODO by responsibility:

- Published root `TODO.md`: problems in this project's code, dependencies, build, installation, tests and project-owned development tools, including useful work outside the current task.
- Private `.codex/TODO.md`: problems in external systems, the local environment and global agent or internal tools whose maintenance is outside this project. Create this file when needed and verify it is ignored by Git and untracked before recording internal details. Never force-add it or copy its internal details into tracked files.

Classify by the component that needs work, not just its filesystem location: game/mod dependencies and the project's test runner still belong in the public TODO. For a mixed issue, keep the project change in the public TODO and external-system diagnostics in the private TODO.

Before adding an item, check the appropriate TODO for the same underlying problem, including differently worded entries. Add useful new context to an existing item instead of creating a duplicate. Keep the item concise and actionable: describe the observed problem, its impact, evidence suitable for that TODO's visibility, and the next step or completion condition. Distinguish observations from suspected causes; a full investigation is not required before recording the issue.

After recording it, continue the current task. A TODO entry does not expand the task's scope or authorize unrelated tooling work. If the problem blocks progress, report the blocker and handle what is necessary to proceed within the existing authorization.
