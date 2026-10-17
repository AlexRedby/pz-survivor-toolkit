# PZ Survivor Toolkit

<img src="PZSurvivorToolkit/common/icon.png" alt="PZ Survivor Toolkit" width="128">

Quality-of-life mods for **Project Zomboid Build 42**: inventory tools, bulk actions, an action queue, crafting plans, visible-item highlights, shared wishlists and compatibility fixes.

## Components

| Component | Version | Purpose |
|---|---|---|
| PZ Survivor Toolkit | 0.1.57 | Inventory tools, queues, crafting plans and compatibility. |
| Survivor Wishlist | 0.1.0 | Personal/shared lists with inventory and crafting integration. |
| Toolkit Java Patches | 0.1.15 | Experimental B42.21 engine fixes; requires ZombieBuddy 2.3.4+. |

The [selected set](SurvivorQoL-selected.ini) requires all three components on the server and every client: **49 Mod IDs / 45 Workshop items**, targeting **B42.21**. Other game builds are outside the Java patches' supported scope.

## Installation

The server owner needs Python 3.10+, JDK 25+ and the ZombieBuddy loader:

```sh
python3 tools/prepare_install.py
```

On Windows, use `py -3` instead of `python3`. Distribute the resulting `dist/SurvivorQoL` folder to all players; recipients need neither Python nor a JDK. The three repository mods have no Workshop downloads and must be copied to every installation.

Follow [the installation guide](MOD_INSTALL.md) for game/JDK paths, server profiles, client setup, Java approvals, Host launchers, updates and backups. Preparation does not modify live profiles.

## Controls

| Entry point | Use |
|---|---|
| **F8** / sidebar flashlight | Toggle visible ground-item highlights. |
| Sidebar tools icon | Open Wishlist, context-menu rules or Toolkit settings. |
| **K** | Open Survivor Wishlist. |
| **Options > Mods** | Configure each component; settings are per player. |
| **Actions** window | Inspect, reorder or cancel supported queued operations. |
| **Plan crafting** | Review prerequisites in native crafting or Neat Crafting. |

The action queue is enabled on fresh profiles and preserves existing preferences. Unsafe or unknown dependencies keep queue controls disabled. See [all controls and limits](docs/FEATURES.md).

## Documentation

| Read this | For |
|---|---|
| [Installation](MOD_INSTALL.md) | Server/client setup, loaders, updates and troubleshooting. |
| [Features and controls](docs/FEATURES.md) | Current behavior, options and compatibility limits. |
| [Changelog](CHANGELOG.md) | Added features, behavior changes and fixes by component version. |
| [Selected mod catalog](USEFUL_MODS.md) | Third-party mod IDs, dependencies, settings and known issues. |
| [Java patches](JavaPatches/README.md) | Engine fixes, server loader and activation checks. |
| [Development](docs/DEVELOPMENT.md) | Tests, packaging, adapters and diagnostics. |
| [Native scenarios](tests/native_queue/README.md) | Isolated game runs and fixture integration. |
| [Open work](TODO.md) | Remaining tasks and completion gates. |

## Compatibility and known issues

See [feature limitations](docs/FEATURES.md#known-limitations) before choosing a setup. [Development scenarios](docs/DEVELOPMENT.md#regression-scenarios) explain what to check; unresolved bugs and their next steps are in [TODO](TODO.md).
