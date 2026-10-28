# Item tags native fixture

[Development](../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../README.md)

This B42.21 RU single-player fixture checks tag rendering, filtering and saved selections through programmatic UI callbacks. The `item-tags` adapter stages it and records scene assertions and screenshots in the common report; physical input and multiplayer are outside its scope.

`manifest.json` lists the five required mod IDs, their load order, five screenshot names, and log markers. Quartermaster is owned by Toolkit; the separate Workshop mod must be disabled. The runner must obtain the selected mods from local sources; this contribution contains no game or Workshop assets, Java launcher, profile, logs, or captures.

From the repository root, prepare a new helper mod directory:

```sh
python3 tests/native_queue/contributions/item-tags/prepare.py \
  --toolkit-source PZSurvivorToolkit \
  --output /tmp/item-tags-helper/QuartermasterScreens
python3 tests/native_queue/contributions/item-tags/test_prepare.py
```

The adapter uses this preparer to copy the Lua fixture, inject assertions for every texture in Toolkit's `TagVisuals.lua`, and write helper metadata, source hashes and the texture list. It refuses to overwrite an existing directory; the shared runner handles the profile and launch.

The scenario checks:

- All configured textures load, including the food/plate, electrical/lightning, medical/cross, tool, material, perishable/clock, fruit/apple, and preserved/jar associations.
- Quartermaster's electrical tag combines matching legacy categories and excludes food; switching to exact categories preserves refinement, shows partial selection, saves exact IDs, and restores them after reopening.
- Native and CleanUI inventory views draw tag pills without changing legacy category projections. The native tag filter returns two food groups; live disable restores all seven groups; an existing Quartermaster picker reacts to live re-enable.
- Five game screenshots capture tag selection, exact refinement, partial selection, CleanUI inventory, and vanilla inventory. The fixture mutates only its disposable test save: it clears player inventory and fills a nearby container.

The adapter fixes Russian language, a 1280x900 window and required mod order. The fixture enables Toolkit's item-tags setting and Better Containers `showAdvancedDisplayCategories=false`, creates its sandbox at the fixed Muldraugh spawn, disables zombies/vehicles through sandbox settings, and enables player god/ghost modes.

Keep these native findings when integrating:

- Inventory page resizing propagates through Java anchor handling after Lua setters. `inventory()` changes the parent first; `reflowInventory()` runs in a later timed step, fixes child bounds, calls `onResize()`, and refreshes. Merging these steps previously left a child beyond the parent.
- The owned picker's scrollbar starts with 10x10 geometry; its clipping can hide tag rows even when items exist. Picker layout updates scrollbar X/height and calls `updateScrollbars()`. Keep the geometry log and visible screenshot check.
- Completion requires `[QM_SCREEN] COMPLETE`, no `[QM_SCREEN] FAIL`, and all five screenshots. The adapter and common report also enforce process completion and runtime audit. Keep generated output and captures outside Git.
