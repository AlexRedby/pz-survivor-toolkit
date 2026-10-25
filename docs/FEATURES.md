# Features and controls

[Overview](../README.md) · [Installation](../MOD_INSTALL.md) · [Changelog](../CHANGELOG.md)

Start with the controls below. Longer workflows have their own guides:

| I want to… | Guide |
|---|---|
| Select, move, inspect or protect items; sort loot; use the Warehouse | [Inventory and storage](features/INVENTORY.md) |
| Inspect, cancel, recover or reorder queued work | [Action queue](features/ACTION_QUEUE.md) |
| Use Navigator, carts or vehicle-part wishes | [Vehicles and carts](features/VEHICLES.md) |
| Configure a third-party mod or check its requirements | [Selected mod catalog](MODPACK.md) |

- [Controls](#controls)
- [Context menus](#context-menus)
- [Crafting plans](#crafting-plans)
- [Exercise storage](#exercise-storage)
- [Survivor Wishlist](#survivor-wishlist)
- [Visibility and rendering](#visibility-and-rendering)
- [Medicine indicators](#medicine-indicators)
- [Compatibility](#compatibility)
- [Known limitations](#known-limitations)

## Controls

- Click the **flashlight icon** beside the left sidebar Inventory button to toggle highlighting. A warm tint and checkmark indicate ON; a grey icon indicates OFF. Hover for the state and current shortcut.
- The adjacent **tools icon** opens Wishlist, context menu rules and Toolkit settings. Settings open scrolled to the Toolkit section. Window buttons retain their text with a shared muted warm style.
- **F8** is the default optional shortcut. Change it using **Options > Mods > PZ Survivor Toolkit > Toggle key**.
- **Options > Mods > PZ Survivor Toolkit** provides the highlight switch, colour picker, toggle key binding and radius (5, 10, 15 or 20 tiles).
- **Show highlight button in sidebar** independently hides or restores the sidebar button; the shortcut and highlight setting still work while it is hidden.
- **Show zero protection changes in grey** toggles clothing comparison colours. Disable it to keep the original game colours.
- Other available feature switches default to on. Settings are saved per client and apply without restarting, using the game's native Mod Options system. Defaults for highlighting: enabled, orange, 15-tile radius. Compatibility fixes and the auto-drink fix remain automatic.

## Context menus

**Group context menu actions** organizes native inventory, world, vehicle and health menus into categories. Common actions appear before secondary and destructive commands. Short menus stay compact; unknown mod commands remain visible, and native recipe/portion submenus keep their structure. Repeated identical commands appear once, while commands for different targets remain separate.

To customize a menu:

1. Open **Context menu rules** from the sidebar tools menu or Toolkit Mod Options.
2. Keep the editor open and right-click an item to capture an example and discover its actions.
3. Search for an action, move it into a group or the main menu, hide it, or restore its automatic placement.

Rules are saved locally and keep applying after the editor closes. Disable the feature to restore the original menus immediately. The setting is hidden while Context Menu Organizer or Context Menu Organizer World is active; no extra Workshop mod is needed.

Back up both `Zomboid/Lua/PZSurvivorToolkit_ContextMenus_a.txt` and `PZSurvivorToolkit_ContextMenus_b.txt` to preserve rules. The old `PZSurvivorToolkit_ContextMenus.ini` imports automatically. If a save fails, the editor reports it and reloads the last verified rules on reopening.

## Crafting plans

Select a recipe in **native crafting** or **Neat Crafting**, then click **Plan crafting**. In Neat Crafting the plan replaces the right-hand recipe details, keeping the recipe list and Wishlist accessible; **< Recipe** returns to the ordinary controls. Native crafting opens a separate plan window. Item icons and quantities show the final result, materials consumed from available stock, reusable tools and ordered intermediate steps. Intermediate ingredients are not counted again as stock requirements. Each step lists its ingredients with **Need / Stock / Make** counts; hover for details. Click an ingredient to choose a material or **Auto**. The choice applies to that ingredient in every use of the same recipe, including prerequisite recipes, and immediately recalculates the whole plan. Choices remain editable if the selected material cannot be obtained.

The quantity is the number of final recipe executions. After changing it, click **Recalculate**, review the result, then **Queue this plan** to add ordinary game actions. If ingredients change before confirmation, review the updated preview and confirm again. Switching recipes or closing Neat Crafting discards its open preview. Disable **Plan prerequisite crafting** in Toolkit Mod Options to hide these controls and restore ordinary crafting immediately.

The planner uses reachable stock, accounts for shared ingredients across the entire chain and reuses intermediate surplus. It respects known recipes, skills, surfaces and workstations. Original item IDs are bound explicitly; favourites and worn/held consumables are excluded. Untouched native auto-filled inputs leave material selection automatic. An explicit native picker choice fixes the material type and prefers the chosen instances first; later repetitions may use other items of that type or newly crafted intermediates. **Auto** in the plan overrides that preference for the current preview. Closing the preview discards its material overrides. Each step checks the actual items again, and tools/books borrowed from containers use native returns. A plan can be cancelled as one operation while waiting or during a supported native crafting step. Remaining dependent steps are removed together; already completed results remain in the inventory.

Planning currently supports deterministic whole-item handcraft recipes. Liquids, partial uses, variable/random outputs, custom recipe callbacks and mixed-type manual inputs stay with ordinary crafting. Generated intermediates must arrive in the character's main inventory; the plan will not take newly appearing shared-container items instead. Search is bounded to 100 craft steps and 32 dependency levels. No materials are reserved on the server: another player's pickup, a broken tool or an ordinary interruption can stop the remaining queue. Project Cook's separate panel and building recipes have no planning control yet.

## Exercise storage

Starting a workout through the native Fitness window puts worn backpacks, pouches and other worn/held inventory containers on the ground. Ordinary clothing and spare bags already in the inventory are not dropped. Afterward, the same bags are picked up and re-equipped when they are still on the same or an adjacent unblocked square and their original worn slots are available. Contents and favourite flags are preserved; another player's bag or a same-type replacement is never substituted. Moving away or someone taking a bag leaves it behind. Native ground-capacity limits still apply; a workout is not started with storage whose placement failed.

This applies with **Show action queue** enabled or disabled. Closing the Fitness window does not remove the native path's pending bag restoration. Workout duration, exercise effects, XP, fatigue and regularity remain native. Heavy forced-drop objects retain their existing handling. Other mods that replace the native Fitness equipment handlers are not covered. Focused checks use B42.21 Lua sources with simulated inventory/world state; full-pack SP/Host gameplay, concurrent pickups and network delivery remain unverified.

## Survivor Wishlist

Survivor Wishlist is included in Toolkit and needs neither Shopping List nor WANTED. Its `PZSurvivorWishlist` namespace, storage, RPCs and **Options > Mods > Survivor Wishlist** settings section remain unchanged.

- Press **K** or choose **Open wishlist** from the sidebar Toolkit tools icon. Search the catalog by item name or full type; a sample or recipe is not required. Set the desired quantity and add the item.
- Native inventory context menus and the native, Neat Crafting, Neat Building and Project Cook crafting windows can add wanted items. Crafting offers results and missing ingredients; choose one alternative when a recipe accepts different items. Fluids and partial uses are not treated as exact piece counts: these entries ask for one suitable container/item and say to check its contents or remaining uses.
- **Sharing** lets you search and select online players to grant editing access, share with your current faction, or both. Existing members keep access when offline. Everyone with access edits the same list; only its owner changes access. The list selector chooses where additions go. All unfinished goals in your accessible lists are highlighted. Concurrent changes against an old revision are rejected with a prompt to review the refreshed list.
- Quantities are shared goals. **Carried by you** counts only your own inventory and carried bags. Mark completed goals manually, so one player's inventory does not silently complete a group objective.
- Highlights apply to visible inventory rows and loose wanted objects currently in your character's field of view, on the same floor and within 15 tiles. Containers, corpses and contents of bags on the ground are never scanned or outlined. CleanUI's two inventory modes and Better Containers' combined item view are supported. The shared world scanner keeps the normal highlight colour/radius separate from Wishlist's colour and fixed 15-tile radius; wanted items use the Wishlist colour.
- **Options > Mods > Survivor Wishlist** controls inventory highlights, ground highlights and crafting controls, plus Wishlist colour and hotkey. Use the native window close button or Escape to close its windows.

Native single-player Wishlist UI, storage and lifecycle have not been validated end to end.

Back up the server directory `Zomboid/Lua/PZSurvivorWishlist/` with the world and preserve its encoded save path on restore. See [backup and server setup](../MOD_INSTALL.md#server). Ground highlighting and the shortcut target the primary local player; secondary split-screen players are unsupported by those controls.

## Visibility and rendering

Only loose world items on the player's current floor and within the configured radius are eligible. There is no item-type whitelist; mod-added items use the same checks.

Highlighting requires the tile to be in the character's **current field of view**, as reported by `IsoGridSquare:isCanSee`. Previously seen tiles alone are insufficient. This is stricter than everything drawn on screen: the game can still draw static items that do not receive a highlight.

The effect uses the game's native rendering. Sprite and atlas items receive an outline; some live 3D models receive a colour tint instead. The mod does not replace the renderer to force identical outlines.

The supported game build is B42.21. Split-screen highlighting has not been validated.

## Medicine indicators

**Medicine indicators** and **Herbal medicine indicators** are two grouped switches for six medicine indicators and two herb indicators, using the optional MoodleFramework independently of Medicine Moodles. Multiplayer readings come from the server and expire after ten seconds without a fresh response. Sleeping-pill strength updates after extra doses; dried herbs use the same native fields. Both switches apply immediately. This section is hidden without MoodleFramework or with the old MedicineMoodlesB42 active, preventing duplicates. Lemongrass reads the native cooldown directly and displays it as a percentage of the maximum; it requires matching Toolkit Java Patches in single-player or on the multiplayer server. Without a supported reading, only that indicator is hidden. No separate countdown or food-action hooks are installed. Full antidepressant onset has not been validated end to end.

## Compatibility

### Multiplayer auto-drink

Enable the toolkit on the server and each client. Each player controls auto-drink through the normal game options or bottle context menu. The server ignores the host's saved global auto-drink switch and keeps using each player's own networked preference, including after `reloadoptions`. The mod never saves server changes into the host's `options.ini`.

Water consumption remains native: this does not enable drinking from backpacks, mixtures or unsafe fluids.

### TV & Radio ReInvented

The TV/radio settings section and its adapters are registered only when TV & Radio ReInvented is active. Installed but disabled mods do not expose settings or receive patches. With TV & Radio ReInvented enabled, inventory and outside clicks keep its windows open. Close the window with the restored X button at its top right. **Options > Mods > PZ Survivor Toolkit > Keep TV/radio windows open** is enabled by default; disabling it immediately restores the original outside-click closure and hidden close button. These settings are local to each client. Native device/range cleanup remains unchanged.

On native macOS, Toolkit Java Patches resolves TV & Radio ReInvented video requests against the actual active mod directory before native caching and loading. The original mod owns its catalog and initialization; Toolkit keeps no separate list of videos. Matching Java Patches is required for this path correction. A separate `Project Zomboid.app/workshop` symlink is no longer required. Keep the complete TV mod installation, including its `.bik` files; a Lua-only copy cannot supply videos. Other platforms keep the upstream video loader; Windows/Linux playback has not been validated. Toolkit now handles device recognition on EN/RU clients itself; keep the old `TVRadioReinventedFix4220` disabled.

**Improve VHS controls** adds direct click-to-eject, tapes from native reachable loot containers and personal bags, and drag-and-drop onto the TV slot. The slot turns green for a VHS and red for an invalid drop. The selection list marks only fully watched tapes with the same checkmark as the inventory. Unfinished tapes have no marker and appear first; history belongs to the current character. Insertion uses native pickup and device actions, with ownership checked on client and server. Disable the option to restore the original TV slot/menu controls.

### Toolkit Java Patches

The separate [Java patch guide](../JavaPatches/README.md) owns the supported engine fixes, bytecode guards, loader setup and activation checks. The complete selected set requires it on the server and every client.

## Known limitations

Verification is primarily on macOS using programmatic game/UI callbacks. Physical mouse/controller use, WAN latency, long sessions and every third-party combination are not covered by those checks. See [development verification](DEVELOPMENT.md#verification-environment) for platform scope and [native scenarios](../tests/native_queue/README.md) for reproducible checks.

Java Patches 0.1.15 guards native body updates and rejects new server treatment requests arriving after their patient disconnects. The earlier clothing-visual synchronization mismatch remains unexplained; successful clinical actions do not establish a clean runtime. The [medical investigation in TODO](../TODO.md#near-term-adapters) records remaining checks.
