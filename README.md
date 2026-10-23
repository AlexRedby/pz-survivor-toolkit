# PZ Survivor Toolkit

<img src="PZSurvivorToolkit/common/icon.png" alt="PZ Survivor Toolkit" width="128">

Quality-of-life mods for **Project Zomboid Build 42**: inventory tools, bulk actions, an action queue, crafting plans, visible-item highlights, shared wishlists and compatibility fixes.

## Components

| Component | Version | Purpose |
|---|---|---|
| PZ Survivor Toolkit | [mod.info](PZSurvivorToolkit/42/mod.info) | Inventory tools, queues, crafting plans, shared Wishlist and compatibility. |
| Toolkit Java Patches | [build definition](JavaPatches/build.py) | Experimental B42.21 engine fixes; requires ZombieBuddy 2.3.4+. |

Current versions come from component metadata; see the [changelog](CHANGELOG.md) for recorded changes.

The [selected set](SurvivorQoL-selected.ini) requires both local mod folders on the server and every client: **54 Mod IDs / 51 Workshop items**, targeting **B42.21**. Wishlist and the complete Quartermaster feature set, including crafting and the storage manifest, are included in Toolkit; existing lists, sorting designations, presets and settings are preserved. Container Capacity Indicator, Item Details, research availability and planting information are also built in, with existing preferences preserved. Disable their separate mods (including HasResearch and SeedSeasonIndicator) and Quartermaster when updating. Other game builds are outside the Java patches' supported scope.

Supported gameplay targets are single-player and **Host** from the game menu on Windows and macOS. The project follows the Build 42 version used by the selected set; older releases and other major game branches are outside its support scope. See the [verification environment](docs/DEVELOPMENT.md#verification-environment) for development checks.

Archery Nexus with Wilderness Progression is selected for bow crafting, Archery progression, arrow recovery and draw endurance/strain. Its B42.21 full-pack and Host behavior remain unverified; see [archery setup and limitations](MOD_INSTALL.md#archery).

## Installation

The server owner needs Python 3.10+, JDK 25+, the [Kotlin 2.4.21 compiler distribution](https://github.com/JetBrains/kotlin/releases/tag/v2.4.21) and the ZombieBuddy loader to prepare Toolkit and Java Patches. The Kotlin path must point to the distribution root containing `lib/` (not its `bin/` directory). The build selects Kotlin in this order: `--kotlin-home`, `KOTLIN_HOME`, then `kotlinc` on `PATH`:

```sh
python3 tools/prepare_install.py
```

On Windows, use `py -3` instead of `python3`. Distribute the resulting `dist/SurvivorQoL` folder to all players; recipients need neither Python, a JDK nor a Kotlin installation. Java and Kotlin project classes target JVM 25, matching B42.21; the private Kotlin runtime is bundled in the Java mod JAR. The two repository mod folders have no Workshop downloads and must be copied to every installation.

Follow [the installation guide](MOD_INSTALL.md) for game/JDK paths, server profiles, client setup, Java approvals, Host launchers, updates and backups. Preparation does not modify live profiles.

## Controls

| Entry point | Use |
|---|---|
| **F8** / sidebar flashlight | Toggle visible ground-item highlights. |
| Sidebar tools icon | Open Wishlist, the Warehouse, context-menu rules or Toolkit settings. |
| **K** | Open Survivor Wishlist. |
| **Options > Mods** | Configure Toolkit features, including the Survivor Wishlist settings section; settings are per player. |
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
| [Blender animation setup](docs/DEVELOPMENT.md#cart-animation-authoring-in-blender) | Prepare an editable scene and native-verified export from a fresh clone. |
| [Cart multiplayer plan](docs/CART_MULTIPLAYER.md) | Current replication, proposed presentation timeline, traffic budget and verification gates. |
| [Native scenarios](tests/native_queue/README.md) | Isolated game runs and fixture integration. |
| [Open work](TODO.md) | Remaining tasks and completion gates. |

## Compatibility and known issues

See [feature limitations](docs/FEATURES.md#known-limitations) before choosing a setup. [Development scenarios](docs/DEVELOPMENT.md#regression-scenarios) explain what to check; unresolved bugs and their next steps are in [TODO](TODO.md).
