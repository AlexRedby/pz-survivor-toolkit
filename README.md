# PZ Survivor Toolkit

<img src="PZSurvivorToolkit/common/icon.png" alt="PZ Survivor Toolkit" width="128">

Quality-of-life tools for **Project Zomboid Build 42**: bulk inventory actions, editable action queues, crafting plans, shared wishlists, storage sorting and visible-item highlights.

Use Toolkit to spend less time managing items and repeated actions. It includes Wishlist and Quartermaster, plus integrations with the project’s [selected mod set](docs/MODPACK.md).

The current target is **B42.21**, in single-player or **Host** from the game menu, on Windows and macOS. The companion Java patches are experimental and require ZombieBuddy. Feature and compatibility limits are listed beside each [feature](docs/FEATURES.md).

## Get started

- **Received a prepared `SurvivorQoL` folder?** Follow [client setup](MOD_INSTALL.md#client); no compiler or Python installation is needed.
- **Preparing the set for yourself or friends?** Follow [prepare once](MOD_INSTALL.md#prepare-once), then the Host/client steps. Preparation leaves live profiles untouched.
- **Updating an existing setup?** Read [update instructions and saved-data migration](MOD_INSTALL.md#update-the-set) before replacing folders or removing separate mods.

## Controls

| Entry point | Use |
|---|---|
| **F8** / sidebar flashlight | Toggle visible ground-item highlights. |
| Sidebar tools icon | Open Wishlist, the Warehouse, context-menu rules or Toolkit settings. |
| **K** | Open Survivor Wishlist. |
| **Options > Mods** | Configure Toolkit features; settings are per player. |
| **Actions** window | Inspect, reorder, cancel or recover supported queued work. |
| **Plan crafting** | Review prerequisites in native crafting or Neat Crafting. |

See [features and controls](docs/FEATURES.md) for workflows, settings and supported actions.

## Find what you need

| Read this | For |
|---|---|
| [Installation and updates](MOD_INSTALL.md) | Prepared folders, Host/client setup, approvals, backups and migration. |
| [Features and controls](docs/FEATURES.md) | Everyday use, inventory/storage, action queues, vehicles and limits. |
| [Changelog](CHANGELOG.md) | Player-visible changes by component version. |
| [Selected mod catalog](docs/MODPACK.md) | Workshop IDs, requirements, settings and known issues for this set. |
| [Java patches](JavaPatches/README.md) | Included engine fixes, Host loader, activation and vehicle logs. |
| [Development](docs/DEVELOPMENT.md) | Checks, builds, architecture, animation authoring and isolated game scenarios. |
| [Open work](TODO.md) | Outstanding engineering tasks and verification gates. |

## Components

| Component | Current version | Purpose |
|---|---|---|
| PZ Survivor Toolkit | [mod.info](PZSurvivorToolkit/42/mod.info) | Player tools, integrated Wishlist/Quartermaster and mod compatibility. |
| Toolkit Java Patches | [build definition](JavaPatches/build.py) | Experimental B42.21 engine fixes, loaded through ZombieBuddy 2.3.4+. |

Both local mod folders are required by the selected INI. Workshop supplies the remaining mods; some integrations still have unverified full-pack or Host behavior. Consult the [installation guide](MOD_INSTALL.md) before loading an existing save.
