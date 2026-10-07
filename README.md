# PZ Survivor Toolkit

![PZ Survivor Toolkit icon](PZSurvivorToolkit/common/icon.png)

A Lua mod for Project Zomboid Build 42. Highlights loose items on the ground to make them easier to find in grass and clutter. Also makes zero protection changes neutral grey in the clothing Wear menu; gains and losses keep the game's configured colours.

## Installation

1. Download this repository using **Code > Download ZIP**, or clone it.
2. Copy the `PZSurvivorToolkit` folder into your `Zomboid/mods` directory, keeping its `common` and `42` subfolders intact.
3. Enable **PZ Survivor Toolkit** in the game's Mods menu and for the save you want to play.

The usual mod directory is `~/Zomboid/mods` on macOS/Linux or `%UserProfile%\Zomboid\mods` on Windows. No additional mod dependency is required.

## Controls

- Click **Items: ON / Items: OFF** at the bottom of the left sidebar to toggle highlighting.
- **F8** is the default optional shortcut. Change it using **Options > Mods > PZ Survivor Toolkit > Toggle key**.
- **Options > Mods > PZ Survivor Toolkit** provides the enabled switch, colour picker, toggle key binding and radius (5, 10, 15 or 20 tiles).
- Defaults: enabled, orange, 15-tile radius. Settings are saved using the game's native Mod Options system.

## Visibility and rendering

Only loose world items on the player's current floor and within the configured radius are eligible. There is no item-type whitelist; mod-added items use the same checks.

Highlighting requires the tile to be in the character's **current field of view**, as reported by `IsoGridSquare:isCanSee`. Previously seen tiles alone are insufficient. This is stricter than everything drawn on screen: the game can still draw static items that do not receive a highlight.

The effect uses the game's native rendering. Sprite and atlas items receive an outline; some live 3D models receive a colour tint instead. The mod does not replace the renderer to force identical outlines.

Requires B42.19 or newer within Build 42. Tested in-game on **B42.21.0, macOS, single-player**, including toggling, settings, pickup and visibility changes through a window with a curtain. Multiplayer and split-screen have not been verified.

The new sidebar button has behavioural checks and has been checked against the installed native UI code. Its in-game visual check is pending.

## Development

Behavioural checks run with Lua 5.1 through Lupa. They use world/UI doubles; they are not visual in-game tests.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install lupa
.venv/bin/python tools/run_tests.py
python3 tools/package_mod.py --check
python3 tools/package_mod.py
```

The package command writes `dist/PZSurvivorToolkit.zip`. Generated packages and local investigations are excluded from Git.

To run the same checks against your installed game's native Mod Options implementation:

```sh
.venv/bin/python tools/run_tests.py --native-mod-options /path/to/media/lua/client/PZAPI/ModOptions.lua
```
