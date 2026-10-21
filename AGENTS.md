# Project rules

## Purpose and sources

PZ Survivor Toolkit is a quality-of-life project for the user's personal gameplay requests, fixes for bugs they have encountered, and integration of third-party mods they like. The repository includes Toolkit (including Survivor Wishlist), Java patches and supporting tools.

The local project sources and its GitHub repository are the source of truth. Unpushed local changes may be newer than GitHub. The copy installed in the game is an installation result, not an independent source of code.

Identify the actual Git repository and current working copy. If the enclosing directory contains several worktrees and an old source copy, do not assume a copy is current just because its directory name matches. Follow the general change-isolation rules.

Check versions, paths, build commands and verification commands against the current project files. Use the existing tools; read the relevant sections of `README.md`, `MOD_INSTALL.md` and `docs/DEVELOPMENT.md` for the task.

## Changes and installation

Do not add features or change gameplay behavior that the user has not requested without discussion, even if you consider them improvements. A bug fix must restore clear, already established expected behavior; agree on an ambiguous outcome first.

Do not automatically install completed changes into the user's local game. Code changes and checks do not authorize overwriting their installed mod. Installation requires a separate request.

Before pushing changes to main, compare each changed component with the latest main. Changes to shipped code, assets or runtime metadata, including behavior-preserving refactors, require a version newer than main for that component: Toolkit uses `PZSurvivorToolkit/42/mod.info`; Java Patches uses the generated metadata in `JavaPatches/build.py`. One bump can cover the complete set of changes delivered together; individual implementation commits do not each need a bump. Record the delivered changes in `CHANGELOG.md` and recheck versions after merging concurrent work. Changes confined to tests, development tools, documentation or agent instructions do not require a mod version bump.

## Supported environment

- Only the current Build 42 version the user plays is supported; older versions do not need support. Moving to another major game branch has not been separately agreed.
- Modes: single-player and Host from the game menu. A separate dedicated server is not a required target environment.
- Players use Windows and macOS, but agent verification on macOS is sufficient for this project. Do not pursue Windows test environments or maintain an active Windows verification requirement; whoever runs the project on Windows checks it there. State the platform actually tested; do not present verification on one platform as verification on the other.
- Run in-game checks with separate test settings and saves, without changing the user's current settings or saves.
- On macOS, native tests first try AeroSpace placement. The default `desktop_mode=auto`, and explicit `current`, fall back to the current desktop when AeroSpace is unavailable, cannot discover the owned window within 30 seconds, or cannot place it. Do not probe display sleep, lock status or Mac availability to decide fallback. Use `aerospace` to require placement without fallback. Keep the owned PID/nonzero GLFW handshake, agent and fresh acknowledgement gates: foreign or malformed window identity, a dead process and an escaped window after successful routing remain errors. CLI unavailability and actual placement-command failures may use fallback only with a valid owned process and GLFW handle. Keep focus/fullscreen suppression; never change the user's display, workspace or focus to enable testing.

## Proportionate checks

Choose the smallest useful check for the change and its risks. Check the affected behavior and related consequences. A build, full test run and game launch are not required after every edit.

- For documentation, check the edited text and affected links; no game launch is needed.
- For local logic, use the related tests. Add a small regression test when it reliably catches a significant error and protects against recurrence. Do not write tests for quantity or to repeat the implementation.
- Check a changed gameplay function in the game with the full mod set if automated checks do not confirm the required behavior. Check network interaction with the corresponding Host scenario.
- Expand coverage when changing a shared mechanism or related integrations, or when a specific error remains unresolved. After sufficient successful verification, do not repeat it without new changes or reasons.

Briefly report the checks performed and significant limitations. Do not claim the entire project has been verified based on a partial run.

## Roles

Carry out your task; each agent is not responsible for a separate search for infrastructure problems. The infrastructure maintainer's duties are described in the project's `pz-infrastructure` skill, which is used only when the user explicitly invokes it.
