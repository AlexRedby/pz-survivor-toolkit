# Item tags native fixture intake

This is an intake copy of the local item-tags fixture for a common native runner. The original fixture was checked in single-player, Russian UI, Project Zomboid B42.21. The portable preparer passed its self-test, and its generated Lua is byte-identical to the fixture executed in the original SP harness. Launching through the common runner remains unverified; this intake is not yet integrated. English, multiplayer, physical mouse/keyboard/controller input, and the full user mod set remain unverified. Calls to UI handlers below are programmatic.

`manifest.json` lists the seven required mod IDs, their load order, five screenshot names, and log markers. The runner must obtain these mods from the local installation; this contribution contains no game or Workshop assets, Java launcher, profile, logs, or captures.

From the repository root, prepare a new helper mod directory:

```sh
python3 tests/native_queue/contributions/item-tags/prepare.py \
  --toolkit-source PZSurvivorToolkit \
  --output /tmp/item-tags-helper/QuartermasterScreens
python3 tests/native_queue/contributions/item-tags/test_prepare.py
```

The preparer copies this contribution's Lua fixture, injects assertions for every texture name currently declared in Toolkit's `TagVisuals.lua`, and writes B42 helper metadata plus source hashes and the texture list. It refuses to overwrite an existing directory. It does not copy the Toolkit mod or dependencies, create a game profile, or launch a process. The common runner must copy the prepared helper alongside all seven locally resolved dependencies and activate `QuartermasterScreens` last.

The scenario checks:

- All configured textures load, including the food/plate, electrical/lightning, medical/cross, tool, material, perishable/clock, fruit/apple, and preserved/jar associations.
- Quartermaster's electrical tag combines matching legacy categories and excludes food; switching to exact categories preserves refinement, shows partial selection, saves exact IDs, and restores them after reopening.
- Native and CleanUI inventory views draw tag pills without changing legacy category projections. The native tag filter returns two food groups; live disable restores all seven groups; an existing Quartermaster picker reacts to live re-enable.
- Five game screenshots capture tag selection, exact refinement, partial selection, CleanUI inventory, and vanilla inventory. The fixture mutates only its disposable test save: it clears player inventory and fills a nearby container.

The runner owns the disposable profile and must use Russian language, 1280x900 windowed rendering, Toolkit's item-tags setting enabled, and Better Containers `showAdvancedDisplayCategories=false`. The fixture creates a sandbox at its fixed Muldraugh spawn, disables zombies/vehicles through sandbox settings, and enables player god/ghost modes. World/map coordinates are scenario data rather than installation paths.

Keep these native findings when integrating:

- Inventory page resizing propagates through Java anchor handling after Lua setters. `inventory()` changes the parent first; `reflowInventory()` runs in a later timed step, fixes child bounds, calls `onResize()`, and refreshes. Merging these steps previously left a child beyond the parent.
- Quartermaster's native scrollbar starts with stale 10x10 geometry; its clipping can hide tag rows even when items exist. Toolkit's adapter updates scrollbar X/height and calls `updateScrollbars()` after layout. Keep the geometry log and visible screenshot check.
- Run one native game owner at a time under the common GUI mutex. Check for an existing user/game session before launch. Track the process/PID group started by the runner and stop only that owned group; never use global Java/game termination. Hold and release the mutex through launch and cleanup.
- VOIP must be disabled before game initialization: `-novoip`, profile `voiceEnable=false`, and the common launcher's native recording-state check with `[QUEUE_TEST] VOICE_DISABLED`. Fail if recording starts (`System create record sound`). Lua preferences alone do not prove that microphone capture stayed closed.
- Require `[QM_SCREEN] COMPLETE`, reject `[QM_SCREEN] FAIL` or early process exit, and verify all five screenshot files before declaring success. The fixture exits after completion/failure; runner timeouts and cleanup remain necessary. Keep output and captures outside Git.
