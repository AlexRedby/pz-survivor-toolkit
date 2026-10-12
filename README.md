# PZ Survivor Toolkit

![PZ Survivor Toolkit icon](PZSurvivorToolkit/common/icon.png)

Quality-of-life mods for Project Zomboid Build 42: inventory filtering and quantity transfers, bulk actions, context-menu organization, an optional action queue, visible ground-item highlights and compatibility fixes for the selected mod set. Shared wishlists and experimental Java engine patches are separate mods in the same repository.

| Component | Version | Installation |
|---|---|---|
| PZ Survivor Toolkit | 0.1.26 | Required; included in the prepared `mods` folder and server INI. |
| Survivor Wishlist | 0.1.0 | Required; included in the prepared `mods` folder and server INI. |
| Toolkit Java Patches | 0.1.2 | Required; built by the preparation command. Needs ZombieBuddy 2.3.4+ in clients and server. |

The selected server INI contains **41 Mod IDs / 37 Workshop items**, including all three repository mods. The complete set targets **B42.21 only** because of the Java patches. Individual feature switches remain available; the action queue is enabled on fresh profiles and preserves an existing choice to disable it. Dated verification results below retain the versions and mod counts actually tested.

## Installation

1. The server owner clones or downloads [this repository](https://github.com/AlexRedby/pz-survivor-toolkit), installs Python 3.10+, JDK 25+ and the ZombieBuddy loader, then runs `python3 tools/prepare_install.py` (`py -3 tools/prepare_install.py` on Windows). See [setup and custom paths](MOD_INSTALL.md#prepare-once) if the game or JDK is not found.
2. Give everyone the resulting `dist/SurvivorQoL` folder. Copy all three folders from its `mods` directory into `Zomboid/mods` on the server and each client. Players receiving this prepared copy need neither Python nor a JDK.
3. Apply its server INI and complete the client/server ZombieBuddy loader setup using the [installation guide](MOD_INSTALL.md). The server downloads the 37 Workshop items; clients download them when joining.

The usual mod directory is `~/Zomboid/mods` on macOS/Linux or `%UserProfile%\Zomboid\mods` on Windows. The preparation command creates an uncompressed, ignored distribution folder; it does not change live game profiles or install third-party loaders.

See the [mod list](USEFUL_MODS.md) and [ordered server INI](SurvivorQoL-selected.ini). All three local mods need manual distribution: they have no Workshop items and cannot download automatically when joining.

## Survivor Wishlist

The separate `PZSurvivorWishlist` folder contains an independent wishlist mod, required and already enabled in our selected INI after the crafting/UI mods. The preparation command includes it for the server and every client. It needs neither Shopping List nor WANTED.

- Press **K** or the sidebar **List** button. Search the catalog by item name or full type; a sample or recipe is not required. Set the desired quantity and add the item.
- Native inventory context menus and the native, Neat Crafting, Neat Building and Project Cook crafting windows can add wanted items. Crafting offers results and missing ingredients; choose one alternative when a recipe accepts different items. Fluids and partial uses are not treated as exact piece counts: these entries ask for one suitable container/item and say to check its contents or remaining uses.
- **Sharing** grants editing to named server usernames (including offline players), your current faction, or both. Everyone with access edits the same list; only its owner changes access. The list selector chooses where additions go. All unfinished goals in your accessible lists are highlighted. Concurrent changes against an old revision are rejected with a prompt to review the refreshed list.
- Quantities are shared goals. **Carried by you** counts only your own inventory and carried bags. Mark completed goals manually, so one player's inventory does not silently complete a group objective.
- Highlights apply to visible inventory rows and loose wanted objects currently in your character's field of view, on the same floor and within 15 tiles. Containers, corpses and contents of bags on the ground are never scanned or outlined. CleanUI's two inventory modes and Better Containers' combined item view are supported. With Toolkit installed, wishlist colours take priority on wanted ground items.
- **Options > Mods > Survivor Wishlist** separately controls inventory highlights, ground highlights and crafting controls, plus colour and hotkey. Use the native window close button or Escape to close its windows.

Lists persist on the server under `Zomboid/Lua/PZSurvivorWishlist/`, separated by the encoded save path; back up this directory with the world. Keep the same save path when restoring it. Files use two alternating checked copies; global ModData is deliberately avoided because vanilla clients can request named global tables without wishlist access. Single-player uses the same validation and storage. No item, recipe or loot content is modified.

Check its folder with `python3 tools/package_mod.py --mod PZSurvivorWishlist --check`. The normal Lua test command also checks the wishlist. Isolated B42.21 macOS multiplayer tests passed on two EN/RU clients with Lua checksums enabled: 33 checks per client alongside the 39 selected mods, five after a complete server/client restart, and 26 with only Wishlist installed. These covered shared editing, conflicting revisions, invitation/faction revocation, persistence, CleanUI modes, Better Containers and the crafting adapters. A final standalone UI pass checked 11 cases per client, including Russian catalog search, native crafting/building layouts, toggles and repeated window cleanup; screenshots were also inspected.

These were programmatic checks in the real game on localhost. Windows/Linux, ordinary Host mode, controller input and long sessions remain unverified. Ground highlighting and the shortcut currently target the primary local player; secondary split-screen players are not supported by those controls.

## Controls

- Click **Items: ON / Items: OFF** at the bottom of the left sidebar to toggle highlighting.
- **F8** is the default optional shortcut. Change it using **Options > Mods > PZ Survivor Toolkit > Toggle key**.
- **Options > Mods > PZ Survivor Toolkit** provides the highlight switch, colour picker, toggle key binding and radius (5, 10, 15 or 20 tiles).
- **Show highlight button in sidebar** independently hides or restores the sidebar button; the shortcut and highlight setting still work while it is hidden.
- **Show zero protection changes in grey** toggles clothing comparison colours. Disable it to keep the original game colours.
- **Cut selected clothing** adds **One item / Cut selected clothing (N)** inside the native cut/rip submenu when at least two eligible garments are selected. Handles mixed cotton, denim and leather using each item's native recipe; denim/leather require a suitable cutting tool. Only selected instances are consumed; favourites, worn/held items and ineligible clothing are skipped. Supports grouped stacks and reachable containers. Disable it independently in Mod Options.
- **Dismantle selected electronics** extends the native dismantling action with **One item** and **Dismantle selected (N)** when at least two eligible items are selected, including grouped stacks and mixed electronics. Both variants retain the native recipe icon. Flashlights keep their battery action alongside dismantling, with the two dismantling variants in a third-level submenu. Supports the native simple electronics, electronic devices, miscellaneous electronics, power bars and battery-lighter dismantling recipes. Favourites and worn/held items are skipped. Each action binds its selected item explicitly and keeps native tools, duration, outputs and XP; tools from reachable containers are transferred once and returned after the batch. Normal cancellation stops the remaining queue. If another player takes a selected item, the rejected pickup safely stops this batch. Toolkit prevents an already-rejected bulk pickup from cancelling another client's same-numbered transfer; ordinary game actions and manual cancellation keep the native network protocol. Disable this feature in Mod Options to hide the command.
- **Remove batteries from selected items** adds **One item / Remove batteries from selected (N)** to the native Remove Battery recipe. Each selected compatible device keeps its identity, the extracted battery uses the game's native charge conversion, and devices picked up from bags or nearby containers use the native return-to-container action after the batch. This covers the native crafting recipe, not radio power-panel actions.
- **Unload selected magazines and firearms** extends native unloading with **One item / Unload selected (N)**. Supports loose magazines and firearms with integral magazines, including mixed selections. Chambered rounds and magazines inserted into weapons keep their separate native actions.
- **Remove attachments from selected weapons** adds **Remove all parts from selected weapons (N)** beside the existing per-part choices. Uses the native detachable-part checks and tool requirements, preserving each part's identity.
- Each bulk feature has its own Mod Options switch. They skip favourites and worn/held items at selection, bind exact selected IDs, and stop the remaining queue on cancellation or stale targets. Native weapon callbacks and queue hooks retain Tidy Up Meister's existing transfer and equipment policies when that mod is active; they do not force an additional return to the previous hand item.
- **Fit Navigator to vehicle dashboard**, shown only with Navigator installed, preserves Navigator's original textured, bevelled monitor housing in a compact shape and tints/positions it for the vanilla dashboard and each Realistic Dashboard driver style. One continuous textured mount sits behind the curved panel edge without covering its controls. Map size follows the dashboard setting within readable bounds; labels and power button retain their native sizes. Routing, animation and dragging stay with Navigator. Disabling the option restores its original UI immediately. Keep `RealisticDash` before `Navigator`.
- **Medicine indicators** and **Herbal medicine indicators** are two grouped switches for six medicine indicators and two herb indicators, using the optional MoodleFramework independently of Medicine Moodles. Multiplayer readings come from the server and expire after ten seconds without a fresh response. Sleeping-pill strength updates after extra doses; dried herbs use the same native fields. Both switches apply immediately. This section is hidden without MoodleFramework or with the old MedicineMoodlesB42 active, preventing duplicates. Lemongrass is an estimated maximum cooldown because its randomized native timer is private; the estimate starts after server-confirmed healing and is not saved across reloads.
- **Grab/Put amount** accepts one positive whole-number budget for the entire selected batch. It captures exact items and destination, rechecks reachability and character identity on confirmation, and uses native transfer actions. Favourites, equipped items and heavy forced-drop objects are skipped. Rejected pickups stop their own batch without cancelling another client's same-numbered transaction. The independent switch is hidden with TakeAnyAmount active.
- With **Better Containers**, Toolkit owns category filters, preserving its proximity and container features. Keep Toolkit before Better Containers and MP Fast Forward; malformed speed commands are rejected before they reach MP Fast Forward. The selected INI already sets this order.
- **Group context menu actions** groups known actions automatically across native inventory, world, vehicle and health context menus. Categories cover food, equipment, health, crafting, maintenance, devices, transfers, world interaction, vehicles, farming and research. Common actions are ordered before secondary and destructive commands using fixed purpose-based priorities: use/equip/heal/read for carried items, pickup for loot, opening/traversal in the world and entry/control/refuelling for vehicles. This is a curated default, not measured usage or adaptive click tracking. Equal-priority actions keep their native relative order; unknown commands and manual placements remain anchored. Native section titles and portion/recipe selectors retain their structure. Exact repeated commands are shown once, including inside native submenus; actions on different targets or with different arguments, tooltips or metadata remain separate. Each selected-item batch operation appears once, keeping the other native single-item choices. Short menus stay compact; unknown mod commands remain visible. Existing callbacks, icons, tooltips and portion/recipe submenus are preserved. **Context menu rules** in the same Mod Options section lets you search actions encountered while playing, place an action in a group or the main menu, hide it, or restore automatic defaults. Rules are saved locally per client. Disable the feature to restore the original menus immediately. This section is hidden while either Context Menu Organizer or Context Menu Organizer World is active. No additional Workshop mod or change to the selected INI is needed.
- **Show action queue** enables the [action queue window](#action-queue), described below. It is enabled by default; an existing disabled preference is preserved.
- Other available feature switches default to on. Settings are saved per client and apply without restarting, using the game's native Mod Options system. Defaults for highlighting: enabled, orange, 15-tile radius. Compatibility fixes and the auto-drink fix remain automatic.

Toolkit v0.1.22 passed five native B42.21 clothing-batch checks per English/Russian client with all 41 selected Mod IDs loaded. Checks covered mixed cotton/denim/leather, grouped selection, native submenus and icons, the live switch, root/bag/nearby-container inputs, tool return, material outputs and protected/unselected survivors. The server confirmed that only the three selected garments per client were consumed. The isolated test used instant timed actions; Windows Host, physical input and long sessions remain unverified.

Toolkit v0.1.23 passed 26 native B42.21 context-menu checks per English/Russian client with all 41 selected Mod IDs loaded. Checks covered exact duplicate filtering, distinct targets and mod metadata, one batch command across repeated native recipe anchors, native menu rendering, two sets of 60 reopen cycles, nested ancestry, dynamic rebuilds, editor/settings rollback and metatable-backed mod entries. The server confirmed a native drop moved exactly one selected item and preserved the spare. Physical input, Windows Host and long sessions remain unverified.

Toolkit v0.1.24 passed 32 native B42.21 context-menu checks per English/Russian client with all 41 selected Mod IDs and Lua checksums enabled. Added checks covered real carried-item and floor-loot priorities, ordering with native world/vehicle callbacks, stable ties, selection identity and empty-panel behavior. The earlier cleanup and server item-conservation checks also passed. This was an isolated macOS localhost run with programmatic UI checks; physical input, Windows Host and long sessions remain unverified.

## Action queue

The movable and resizable **Actions** window shows the game's existing queue, with item/action icons, current progress and mouse-wheel scrolling. It has no five-action limit. It is enabled on fresh profiles; disable **Options > Mods > PZ Survivor Toolkit > Show action queue** to hide it. Existing saved choices are preserved.

- Multi-step operations collapse into a task row, such as **Unload Rounds**, instead of being named after their initial preparation. Common action labels use EN/RU translations and retain item or recipe names. Mixed tasks are shown as **Multiple actions**; unknown mod actions retain their type for identification. Click **+** to see each native step or **-** to collapse it. The count includes remaining preparation, action and return steps; it is not an item/completion counter. The header shows the current step's progress while that operation runs.
- Expand an operation and click an enabled cross to cancel an eligible step individually. Reading and native furniture/door dismantling can be stopped while preserving the later queue. Supported waiting book, world-dismantling and Toolkit bulk actions can also be removed. Headers have no cancel-all control.
- Drag a waiting row or its header to move the complete operation, including preparation and returns. Moving it before active reading pauses the book, performs the moved operation and resumes reading from native saved progress. Other active actions remain protected.
- Steps that share an item or known world target cannot be reordered across each other. Individual transfers, preparation/returns, callbacks, linked steps and unaudited action types retain cancellation protection. Hover a disabled control for the reason.

The window hides and releases its displayed rows when the queue empties, the player dies or the option is disabled. Ordinary game cancellation still clears the queue. There is no dedicated hotkey or close button. Automatic prerequisite crafting is not implemented. Asynchronous mod callbacks that enqueue outside a native operation scope can appear as separate rows; arbitrary mod dependencies cannot be inferred.

Queue regression checks use the installed game's Lua queue, base action, reading action and list geometry with simulated Java/UI lifecycle. Run them with `--native-action-root /path/to/media/lua`; the default test command skips those native-source checks without that path.

Toolkit v0.1.25 passed **46 native queue checks plus 12 door-dismantling checks per EN/RU client** on an isolated B42.21 macOS dedicated server with all **41 selected Mod IDs** and Lua checksums enabled. Checks covered collapsed/expanded batches, per-step cancellation, whole-operation dragging, book preemption/resumption, linked-step protection, source-container returns, ordinary cancellation and death cleanup. Server checks confirmed unique item IDs, ammunition conservation, saved book pages/XP, and fuel use only for the retained door dismantle. Native screenshots were inspected in both languages; the selected Tidy 42.20 equipment policy was preserved. One fixture-spawn weapon-sync warning appeared before queue actions; subsequent server inventory/ammunition checks passed. Java loader transformations were confirmed on the server and both clients. These checks use programmatic UI callbacks and shortened reading times; physical input, respawn, split-screen, WAN jitter, Windows/Linux and long sessions remain unverified.

Toolkit v0.1.26 passed **46 native queue checks per EN/RU client** on 13 October 2026 with the same 41-Mod-ID B42.21 macOS dedicated-server setup and Lua checksums enabled. Added assertions verify translated equipment/unload labels and task headings for unloading and container reading. Collapsed/expanded screenshots were inspected in both languages: the remaining step count stays separate from the title, and the current native step retains its progress. Cancellation, dragging, item/ammunition conservation and reading preemption/resumption also passed. Lua regressions cover mixed tasks, changing remaining work, unknown actions and long-title clipping. This run used programmatic UI callbacks and shortened reading times; Windows/Linux, physical input and long sessions were not exercised.

## Recorded verification

These results describe the builds and selected sets used in each scenario, not a claim that every current feature was exercised together. Current installation uses the 41-mod INI listed above.

On 13 October 2026, the user reported that the installed set works without observed issues and closed the longer-session follow-up. They attributed the previously reported multiplayer combat/grapple jerks to a poor internet connection, so that investigation is no longer planned. These are user reports; the automated coverage remains scoped to the runs below.

On 12 October 2026, the complete 41-Mod-ID set from `tools/prepare_install.py` passed a native B42.21 macOS smoke test on an isolated dedicated server and two EN/RU clients with Lua checksums enabled: 33 wishlist/UI/shared-editing checks per client, no failures. The Java loader transformed the server's media class and both clients' zombie/vehicle classes. The build's native vehicle and media regressions also passed. This checks combined loading and the exercised integrations on macOS dedicated-server clients. Host verification was subsequently confirmed by the user on 13 October 2026; physical input, every mod feature and long sessions were not covered by this automated run.

Toolkit v0.1.14 passed 16 native B42.21 bulk-dismantling multiplayer checks per English/Russian client with seven relevant Mod IDs loaded, including CleanUI, Better Containers, Neat Crafting and Tidy Up Meister. Checks covered native icons/submenus, the third-level flashlight menu and preserved battery action, actual flashlight dismantling, exact mixed selections, personal-bag and nearby-container transfers, tool return, native XP, cancellation and a removed selected item. Both clients then queued the same four shared-container item IDs with the same transaction number: one queue stopped on rejection, while the other produced exactly four dismantles and four scrap items; unselected/favourite items remained intact. No gameplay Lua exceptions occurred in the final short localhost scenario. The full selected mod set, physical mouse/controller input and long sessions have not been checked for this feature.

Toolkit v0.1.15 passed 36 additional native B42.21 multiplayer checks per English/Russian client with the same seven relevant mods. The three new actions ran normally on exact selected items in the main inventory, a personal bag and a nearby crate; the server verified three batteries with native charge conversion, nine returned rounds and all six original attachment IDs per client. Checks also covered native menus, individual toggles, cancellation, stale targets and simultaneous extraction from the same two shared flashlight IDs without duplicate outputs. No gameplay Lua exceptions occurred. This remains a short localhost check, not coverage of the full mod set or long sessions.

Toolkit v0.1.19 compact textured Navigator integration was checked in 12 native B42.21 views: vanilla plus all Realistic Dashboard driver styles, trunk/no-trunk, HAM/value radio, all four dashboard sizes and restoring the regular size. The dashboard views used the full 42-mod set configured from the selected INI, on an isolated dedicated server with one English client and Lua checksums enabled. Routes, native power input, map/overlay geometry, dragging, closing and live original-UI rollback passed; native dashboard volume, TV & Radio Reinvented and Smart Radial Menu also passed. Custom dashboard mods and split-screen remain untested.

Toolkit v0.1.16 passed 54 native B42.21 medicine checks per English/Russian client with all 42 selected Mod IDs and Lua checksums enabled. The server confirmed actual consumption and effects for every medicine, both herbs and their dried variants, including a second sleeping-pill dose and ineffective repeated lemongrass. Checks covered server timer decay, translated tooltips, independent toggles and effect expiry; the expiry fixture shortened native remaining values after consumption. No gameplay Lua exceptions occurred. Full antidepressant onset, long sessions and live installation remain untested.

Toolkit v0.1.20 passed 86 native B42.21 checks per English/Russian client with the final 39 selected Mod IDs, an isolated dedicated server and Lua checksums enabled. Checks covered all eight independent medicine indicators, native consumption and freshness, quantity dialogs/mixed stacks/protected items, CleanUI category selection, malformed MPFF commands and native furniture/held TV-radio panels without the three removed dependencies. Both clients attempted the same three shared-container IDs and started the same transaction number within milliseconds; the server confirmed exactly one copy of each transferred item and untouched unselected/favourite items. Rejected quantity pickups use the existing bulk transfer guard. No gameplay Lua exceptions occurred. This is a short macOS localhost smoke: physical input, Windows Host, long sessions and production-world migration remain untested; shortened medicine expiry and estimated lemongrass cooldown retain the limits above.

Automatic context-menu organization passed 20 native B42.21 multiplayer checks per English/Russian client with all 39 selected Mod IDs and Lua checksums enabled. Checks covered original option identity and metadata, actual clock/flashlight menus, third-level selectors, 60 reopen cycles, single-context ancestor navigation, late insertion and child rebuild, live rollback, saved overrides and the native editor. The server confirmed exactly one dropped item per client and an untouched spare. This was a short isolated macOS localhost check; physical mouse/controller input, Windows and long sessions remain unverified.

## Visibility and rendering

Only loose world items on the player's current floor and within the configured radius are eligible. There is no item-type whitelist; mod-added items use the same checks.

Highlighting requires the tile to be in the character's **current field of view**, as reported by `IsoGridSquare:isCanSee`. Previously seen tiles alone are insufficient. This is stricter than everything drawn on screen: the game can still draw static items that do not receive a highlight.

The effect uses the game's native rendering. Sprite and atlas items receive an outline; some live 3D models receive a colour tint instead. The mod does not replace the renderer to force identical outlines.

Requires B42.19 or newer within Build 42. Tested in-game on **B42.21.0, macOS, single-player**, including toggling, settings, pickup and visibility changes through a window with a curtain. Two local multiplayer clients have also been tested on B42.21. Split-screen has not been verified.

The Toolkit sidebar visibility option has behavioural checks against the installed native UI code; a dedicated in-game visual check of that option is not recorded.

## Multiplayer auto-drink

Enable the toolkit on the server and each client. Each player controls auto-drink through the normal game options or bottle context menu. The server ignores the host's saved global auto-drink switch and keeps using each player's own networked preference, including after `reloadoptions`. The mod never saves server changes into the host's `options.ini`.

Water consumption remains native: this does not enable drinking from backpacks, mixtures or unsafe fluids. Tested on B42.21 with two local clients, both on a dedicated server and through Host. Checks cover opposing preferences, Options changes, empty/refilled bottles, server option reload and ordinary automatic drinking with bottle/thirst updates received by the client.

## CleanUI / Container Capacity Indicator

When using both mods, load them in this order: **NeatUI Framework, CleanUI, PZ Survivor Toolkit, Container Capacity Indicator**. Toolkit aligns CCI bars with CleanUI's visible inventory icons, including equipment headers, hidden equipment, expanded stacks and scaled icons. CCI keeps its own capacity calculations, colours and magazine setting. Toolkit preserves its item and container-button bars when CleanUI switches between enhanced and vanilla inventories, including icon views; it also supplies the alpha omitted by B42's native icon renderer. Without that pair, the adapter does nothing. If CCI loads before Toolkit, the adapter logs the required order and leaves its renderer unchanged.

Checked in-game on B42.21 with CleanUI 2.9.7 and CCI 1.2.0, including container reordering and 140% icon scale. Toolkit v0.1.12 passed 15 checks per English/Russian client with all 38 selected Mod IDs loaded: enhanced/vanilla details and icons, container-button bars, repeated mode switches and native item transfers. No gameplay exceptions occurred during this short localhost scenario.

## TV & Radio ReInvented

The TV/radio settings section and its adapters are registered only when TV & Radio ReInvented is active. Installed but disabled mods do not expose settings or receive patches. With TV & Radio ReInvented enabled, inventory and outside clicks keep its windows open. Close the window with the restored X button at its top right. **Options > Mods > PZ Survivor Toolkit > Keep TV/radio windows open** is enabled by default; disabling it immediately restores the original outside-click closure and hidden close button. These settings are local to each client. Native device/range cleanup remains unchanged.

On native macOS, Toolkit loads the 16 videos shipped with TV & Radio ReInvented v1.3 from the actual active mod directory. A separate `Project Zomboid.app/workshop` symlink is no longer required. Keep the complete TV mod installation, including its `.bik` files; a Lua-only copy cannot supply videos. Other platforms keep the upstream video loader. Toolkit now handles device recognition on EN/RU clients itself; keep the old `TVRadioReinventedFix4220` disabled.

An earlier native B42.21 macOS test with English/Russian clients, CleanUI, CCI and the then-required external translation fix passed 18 checks per client with the old symlink absent. Checks covered all 16 video textures, synchronized VHS playback, native close-button callbacks, live option changes and out-of-range cleanup. The later v0.1.20 test above checked device recognition without that external fix. Other platforms remain unverified.

**Improve VHS controls** adds direct click-to-eject, tapes from native reachable loot containers and personal bags, and drag-and-drop onto the TV slot. The slot turns green for a VHS and red for an invalid drop. The selection list marks only fully watched tapes with the same checkmark as the inventory. Unfinished tapes have no marker and appear first; history belongs to the current character. Insertion uses native pickup and device actions, with ownership checked on client and server. Disable the option to restore the original TV slot/menu controls.

Toolkit v0.1.12 passed 18 native B42.21 VHS multiplayer checks per English/Russian client with all 38 selected Mod IDs loaded, including container/bag/floor pickup, direct ejection, character-specific history and checkmarks, invalid/occupied drops, stale selections, server ownership and tape conservation. No gameplay exceptions occurred during this short localhost scenario. Combined with the 15 inventory/CCI checks, each client passed 33 checks. Physical mouse/controller input and long sessions remain unverified.

## Vehicle mechanics

Right-click a removable part in the vehicle mechanics window and select **Uninstall to ground**. The part is left at your character's feet when removal succeeds, including light bulbs and heavy parts; there is no weight threshold. Tools, skills, work duration and the chance of damaging a part remain native. The original **Uninstall** action keeps its usual inventory destination and its fallback to the ground when the inventory has no room. Disable **Uninstall vehicle parts to ground** in Mod Options to hide the extra command; already queued actions keep their chosen destination.

In multiplayer, install Toolkit on the server and every client. No additional mod or Java patch is required for this action.

Toolkit v0.1.13 passed 13 native B42.21 checks per English/Russian client and six server checks: light/heavy parts (test weights 0.1 and 1000), radio, hood/tool actions, ordinary inventory removal and cancellation. Every successful ground removal left exactly one item visible to both clients, including on tiles already holding more than 50 weight. The isolated test used instant timed actions and only Toolkit plus its test helper. Windows Host mode, modded vehicles and physical input remain unverified.

## Toolkit Java Patches

[Toolkit Java Patches](JavaPatches/README.md) is an independent, experimental Java mod for B42.21, required and already enabled in the selected set. Its source, build script and tests live in `JavaPatches/`; `tools/prepare_install.py` builds and includes it with the two Lua mods. ZombieBuddy must load in each client and the server process. See its guide for Host launchers, dedicated-server setup, supported fixes and test limits.

The Java patches also cancel the old server stop timer when restarting a VHS cassette. The original engine loses playback after rapid Stop/Play; the patched B42.21 server and two English/Russian clients passed eight checks each, including synchronized controls, cassette dialogue, 62.5 XP per character and normal completion. The Java loader must run in the server process. The user confirmed Host verification on 13 October 2026; this confirmation is separate from the automated dedicated-server checks recorded above.

## Development

Behavioural checks run with Lua 5.1 through Lupa. They use world/UI doubles; they are not visual in-game tests.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install lupa
.venv/bin/python tools/run_tests.py
python3 tools/package_mod.py --check
python3 tools/package_mod.py --mod PZSurvivorWishlist --check
python3 -m unittest discover -s tests -p 'test_prepare_install.py'
python3 -m unittest discover -s JavaPatches/tests
python3 tools/prepare_install.py --check
```

The CCI regression can also run against the installed third-party source with `--cci-source /path/to/ContainerCapacityIndicator.lua`. VHS menu, sorting, drop validation and live toggle checks run by default; add `--tv-source /path/to/RWMMergedTV.lua --native-radio-root /path/to/media/lua/client` to also exercise the native media actions and drag parser.

Independent medicine checks can use the installed framework with `--medicine-framework-source /path/to/MF_ISMoodle.lua`. Use `--native-inventory-context-menu /path/to/ISInventoryPaneContextMenu.lua` for actual transfer callbacks and the sibling native text-box constructor/callback. `--mpff-source /path/to/MPFastForward/media/lua` and `--bc-filter-source /path/to/CategoryFilters.lua` exercise the upstream modules and early compatibility gates; without these paths, those source checks report SKIP.

Vehicle ground-placement regressions run by default. Add `--native-uninstall /path/to/media/lua/shared/Vehicles/TimedActions/ISUninstallVehiclePart.lua` to exercise the installed game's actual removal completion, including failure, callbacks and its existing ground fallback.

Action queue checks require `--native-action-root /path/to/media/lua`. Wishlist crafting checks can additionally inspect native menu callbacks and installed adapters with `--wishlist-game-root /path/to/game/Java-directory --wishlist-workshop-root /path/to/steamapps/workshop/content/108600`.

For a developer-only archive of one Lua mod, run `python3 tools/package_mod.py` or add `--mod PZSurvivorWishlist`. Output goes to `dist/<mod>.zip` and is excluded from Git. Use `tools/prepare_install.py` for the complete installable set; it creates no archive.

To run the same checks against your installed game's native Mod Options implementation:

```sh
.venv/bin/python tools/run_tests.py --native-mod-options /path/to/media/lua/client/PZAPI/ModOptions.lua
```
