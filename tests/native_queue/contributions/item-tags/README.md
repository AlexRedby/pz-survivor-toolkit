# Item tags native fixture intake

[Development](../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../README.md)

The common runner stages this B42.21 RU/SP fixture through `tools/queue_checks/adapters/auxiliary.py`, with exact scene assertions and screenshots. It uses the current Toolkit and listed UI mods; pass `--mods selected` with a pack lock to run the complete set. Verification belongs in per-run reports. UI handler calls are programmatic; this scenario does not cover English, multiplayer or physical input.

`manifest.json` lists the five required mod IDs, their load order, five screenshot names, and log markers. Quartermaster is owned by Toolkit; the separate Workshop mod must be disabled. The runner must obtain the selected mods from local sources; this contribution contains no game or Workshop assets, Java launcher, profile, logs, or captures.

From the repository root, prepare a new helper mod directory:

```sh
python3 tests/native_queue/contributions/item-tags/prepare.py \
  --toolkit-source PZSurvivorToolkit \
  --output /tmp/item-tags-helper/QuartermasterScreens
python3 tests/native_queue/contributions/item-tags/test_prepare.py
```

The preparer copies this contribution's Lua fixture, injects assertions for every texture name currently declared in Toolkit's `TagVisuals.lua`, and writes B42 helper metadata plus source hashes and the texture list. It refuses to overwrite an existing directory. It does not copy the Toolkit mod or dependencies, create a game profile, or launch a process. The common runner must copy the prepared helper alongside the locally resolved dependencies and activate `QuartermasterScreens` last.

The scenario checks:

- All configured textures load, including the food/plate, electrical/lightning, medical/cross, tool, material, perishable/clock, fruit/apple, and preserved/jar associations.
- Quartermaster's electrical tag combines matching legacy categories and excludes food; switching to exact categories preserves refinement, shows partial selection, saves exact IDs, and restores them after reopening.
- Native and CleanUI inventory views draw tag pills without changing legacy category projections. The native tag filter returns two food groups; live disable restores all seven groups; an existing Quartermaster picker reacts to live re-enable.
- Five game screenshots capture tag selection, exact refinement, partial selection, CleanUI inventory, and vanilla inventory. The fixture mutates only its disposable test save: it clears player inventory and fills a nearby container.

The runner owns the disposable profile and must use Russian language, 1280x900 windowed rendering, Toolkit's item-tags setting enabled, and Better Containers `showAdvancedDisplayCategories=false`. The fixture creates a sandbox at its fixed Muldraugh spawn, disables zombies/vehicles through sandbox settings, and enables player god/ghost modes. World/map coordinates are scenario data rather than installation paths.

Keep these native findings when integrating:

- Inventory page resizing propagates through Java anchor handling after Lua setters. `inventory()` changes the parent first; `reflowInventory()` runs in a later timed step, fixes child bounds, calls `onResize()`, and refreshes. Merging these steps previously left a child beyond the parent.
- The owned picker's scrollbar starts with 10x10 geometry; its clipping can hide tag rows even when items exist. Picker layout updates scrollbar X/height and calls `updateScrollbars()`. Keep the geometry log and visible screenshot check.
- Run one native game owner at a time under the common GUI mutex. Check for an existing user/game session before launch. Track the process/PID group started by the runner and stop only that owned group; never use global Java/game termination. Hold and release the mutex through launch and cleanup.
- VOIP must be disabled before game initialization: `-novoip`, profile `voiceEnable=false`, and the common launcher's native recording-state check with `[QUEUE_TEST] VOICE_DISABLED`. Fail if recording starts (`System create record sound`). Lua preferences alone do not prove that microphone capture stayed closed.
- Require `[QM_SCREEN] COMPLETE`, reject `[QM_SCREEN] FAIL` or early process exit, and verify all five screenshot files before declaring success. The fixture exits after completion/failure; runner timeouts and cleanup remain necessary. Keep output and captures outside Git.
