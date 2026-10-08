# PZ Survivor Toolkit

![PZ Survivor Toolkit icon](PZSurvivorToolkit/common/icon.png)

A Lua mod for Project Zomboid Build 42. Highlights loose items on the ground to make them easier to find in grass and clutter. Also makes zero protection changes neutral grey in the clothing Wear menu; gains and losses keep the game's configured colours. Fixes multiplayer auto-drink preferences shared accidentally through the host's saved options.

## Installation

1. Download the ready-to-install [PZSurvivorToolkit.zip v0.1.4](https://raw.githubusercontent.com/AlexRedby/pz-survivor-toolkit/main/PZSurvivorToolkit.zip).
2. Copy the `PZSurvivorToolkit` folder into your `Zomboid/mods` directory, keeping its `common` and `42` subfolders intact.
3. Enable **PZ Survivor Toolkit** in the game's Mods menu and for the save you want to play.

The usual mod directory is `~/Zomboid/mods` on macOS/Linux or `%UserProfile%\Zomboid\mods` on Windows. No additional mod dependency is required.

For our selected multiplayer mod set, see the [server/client installation steps](MOD_INSTALL.md), [mod list](USEFUL_MODS.md) and [ordered server INI](SurvivorQoL-selected.ini). Toolkit must be installed manually on the server and every client; it has no Workshop item.

## Controls

- Click **Items: ON / Items: OFF** at the bottom of the left sidebar to toggle highlighting.
- **F8** is the default optional shortcut. Change it using **Options > Mods > PZ Survivor Toolkit > Toggle key**.
- **Options > Mods > PZ Survivor Toolkit** provides the enabled switch, colour picker, toggle key binding and radius (5, 10, 15 or 20 tiles).
- Defaults: enabled, orange, 15-tile radius. Settings are saved using the game's native Mod Options system.

## Visibility and rendering

Only loose world items on the player's current floor and within the configured radius are eligible. There is no item-type whitelist; mod-added items use the same checks.

Highlighting requires the tile to be in the character's **current field of view**, as reported by `IsoGridSquare:isCanSee`. Previously seen tiles alone are insufficient. This is stricter than everything drawn on screen: the game can still draw static items that do not receive a highlight.

The effect uses the game's native rendering. Sprite and atlas items receive an outline; some live 3D models receive a colour tint instead. The mod does not replace the renderer to force identical outlines.

Requires B42.19 or newer within Build 42. Tested in-game on **B42.21.0, macOS, single-player**, including toggling, settings, pickup and visibility changes through a window with a curtain. Two local multiplayer clients have also been tested on B42.21. Split-screen has not been verified.

The new sidebar button has behavioural checks and has been checked against the installed native UI code. Its in-game visual check is pending.

## Multiplayer auto-drink

Enable the toolkit on the server and each client. Each player controls auto-drink through the normal game options or bottle context menu. The server ignores the host's saved global auto-drink switch and keeps using each player's own networked preference, including after `reloadoptions`. The mod never saves server changes into the host's `options.ini`.

Water consumption remains native: this does not enable drinking from backpacks, mixtures or unsafe fluids. Tested on B42.21 with two local clients, both on a dedicated server and through Host. Checks cover opposing preferences, Options changes, empty/refilled bottles, server option reload and ordinary automatic drinking with bottle/thirst updates received by the client.

## CleanUI / Container Capacity Indicator

When using both mods, load them in this order: **NeatUI Framework, CleanUI, PZ Survivor Toolkit, Container Capacity Indicator**. Toolkit aligns CCI bars with CleanUI's visible inventory icons, including equipment headers, hidden equipment, expanded stacks and scaled icons. CCI keeps its own capacity calculations, colours and magazine setting. Without that pair, the adapter does nothing. If CCI loads before Toolkit, the adapter logs the required order and leaves its renderer unchanged.

Checked in-game on B42.21 with CleanUI 2.9.7 and CCI 1.2.0 in the enhanced details view, including container reordering and 140% icon scale. Switching to vanilla or icon views at runtime has not been verified. The full selected mod set has not been tested together in multiplayer.

## TV & Radio ReInvented

With TV & Radio ReInvented enabled, inventory and outside clicks keep its windows open. Close the window with the restored X button at its top right. **Options > Mods > PZ Survivor Toolkit > Keep TV/radio windows open** is enabled by default; disabling it immediately restores the original outside-click closure and hidden close button. These settings are local to each client. Native device/range cleanup remains unchanged.

On native macOS, Toolkit loads the 16 videos shipped with TV & Radio ReInvented v1.3 from the actual active mod directory. A separate `Project Zomboid.app/workshop` symlink is no longer required. Keep the complete TV mod installation, including its `.bik` files; a Lua-only copy cannot supply videos. Other platforms keep the upstream video loader. The translation fix is still needed for TV device recognition on Russian clients.

Checked on native B42.21 macOS with an English and Russian client, CleanUI, CCI and the translation fix: 18 checks per client passed with the old symlink absent. Checks cover all 16 valid video textures, synchronized VHS playback, native close-button callbacks, live option changes and out-of-range cleanup. This was a short localhost multiplayer test; the full selected mod set and other platforms remain unverified.

## Development

Behavioural checks run with Lua 5.1 through Lupa. They use world/UI doubles; they are not visual in-game tests.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install lupa
.venv/bin/python tools/run_tests.py
python3 tools/package_mod.py --check
python3 tools/package_mod.py
```

The CCI regression can also run against the installed third-party source with `--cci-source /path/to/ContainerCapacityIndicator.lua`.

The package command writes `dist/PZSurvivorToolkit.zip`; this directory and local investigations are excluded from Git. The published installation archive is `PZSurvivorToolkit.zip` at the repository root. Update it with `python3 tools/package_mod.py --output PZSurvivorToolkit.zip` when publishing mod changes.

To run the same checks against your installed game's native Mod Options implementation:

```sh
.venv/bin/python tools/run_tests.py --native-mod-options /path/to/media/lua/client/PZAPI/ModOptions.lua
```
