# Useful Mods and Settings for Project Zomboid

Reference for the selected third-party mods, Workshop IDs, dependencies, load order, settings and known caveats. The [server INI](SurvivorQoL-selected.ini) defines the current B42.21 selection. See [installation instructions](MOD_INSTALL.md) for the portable server/client INI and local repository mods. Toolkit features are documented in [FEATURES](docs/FEATURES.md); Java Patches setup is in [JavaPatches/README.md](JavaPatches/README.md).

## 1 Show VHS Skills in Tooltip

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3716522633) · Workshop `3716522633` · Mod `VHSSkillNameInTooltip`

Shows skills and recipes taught by VHS tapes in the native item tooltip. B41/B42 are reported; the author tested B41.78.19 and B42.20, including multiplayer. WYD series support is reported on B42; load after WYD mods. Display of already-known recipes has not been confirmed.

Toolkit reads this mod's catalog and translations and draws the extra rows within native tooltip measurement and placement. The mod remains selected; its independent render wrapper is suppressed before game start.

## 2 MP Fast Forward

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3738738086) · Workshop `3738738086` · Mod `MPFastForward`

Restores fast-forward in multiplayer/co-op. Agreement can be required from all players or controlled by an administrator. Configure speed, control mode and zombie-check radius in Sandbox settings; the author says movement or a nearby zombie stops fast-forward. B42.19+ is reported. Recent reports mention a disappearing interface.

## 3 Better Containers

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3586216562) · Workshop `3586216562` · Mod `EURY_CONTAINERS`

Combines nearby accessible loot, filters categories, manages container names/icons/colours/order and supports nested bags. Toolkit supplies Smart Deposit for its proximity view: matching item type, then category, then a suitable available container; otherwise the item stays with the player. Drag feedback marks items that cannot be placed. Manage Containers assignments are not used.

- Disable built-in Advanced Display Categories; load `organizedCategories_core` last. Nested Containers Player/Loot preserves standard multiplayer restrictions.
- With CleanUI, Toolkit owns the category filter. Use its Category header control; CleanUI search still filters results.
- A bag inside a crate cannot be addressed by the native multiplayer protocol. For deeper crate contents, carry the whole bag, work with it, then return it to the crate. Deeper nested ground bags can trigger `ContainerID.set`; disabling UI protection does not resolve the protocol limit.

## 4 Clean HotBar

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3461263912) · Workshop `3461263912` · Mod `CleanHotBar`

Displays held-item and hotbar details including durability, ammunition, jams, battery charge and container contents. Slot order, size and transparency are configurable. Reported for B42.12.3–B42.21.0, including multiplayer and dedicated servers. Conflicts are possible with other hotbar replacements; the author recommends loading it late. No separate UI framework is required.

## 5 Neat Crafting

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3502080466) · Workshop `3502080466` · Mod `Neat_Crafting`

Searchable crafting interface with filters, alternate materials and crafting chains. Requires [NeatUI Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3508537032) (`3508537032`, `NeatUI_Framework`); load Framework first and add both to the server. The author reports a conflict with `what can i craft` and its add-on; other crafting-menu replacements may conflict. To remove it from an existing world, follow the author's Safe Uninstall Support instructions; do not enable that support and the main mod together.

## 6 Project Cook

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3490188370) · Workshop `3490188370` · Mod `Project_Cook`

Separate cooking window with nearby ingredients, a queue, nutrition details and nearby-stove controls. Requires [NeatUI Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3508537032) (`3508537032`, `NeatUI_Framework`); load Framework first. Optional `Project_Cook_Pixel_Icon_Pack` changes icons and loads after the main mod. Recent player reports mention multiplayer cooking-action problems; verify on the target server.

## 7 Tidy Up Meister

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=2769706949) · Workshop `2769706949` · Mod `P4TidyUpMeister`

Restores held equipment and returns temporarily removed items after actions. Automatic re-equipping can be disabled. Some returns overlap with vanilla behavior since B42.8. Unusual actions from other mods may be misidentified.

## 8 Moodle Descriptions Expanded

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3389003300) · Workshop `3389003300` · Mod `B42MoodleDescriptionsExpanded`

Expands moodle tooltips with explanations and numerical penalties. Values reflect author/translator interpretation and may need rechecking after game updates. Other moodle-description mods can conflict; the author recommends loading after moodle mods. B42 is reported; B42.21 is not separately confirmed.

## 9 Detailed Descriptions for Occupations and Traits

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3387957272) · Workshop `3387957272` · Mod `DetailedDescriptionsForOccupationsAndTraits`

Adds numerical effects, known recipes and foraging bonuses to occupation and trait descriptions. The page is titled `[B42.20]`; the author separately confirmed B42.21 on 1 October 2026. A Russian translation is available for B42.20. Multiplayer has not been separately confirmed by the author.

## 10 Peek a View

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3710281407) · Workshop `3710281407` · Mod `PeekAView`

Fades walls and trees and reveals the upper floor while climbing stairs without changing vanilla line-of-sight rules. Requires [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) (`3619862853`, `ZombieBuddy`); add both to the server and complete ZombieBuddy setup on each player. Approve the PeekAView JAR at its first-launch prompt. Custom stairs and basement mods can conflict with stair visibility.

## 12 Share Map Notes

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3676995511) · Workshop `3676995511` · Mod `PZShareMapNotes`

Shares map symbols and notes and adds synced freehand drawing. Sharing can be limited to everyone, faction or safehouse members. Drawing requires a pen and erasing an eraser by default; per-player and server limits are configurable. The author warns that excessive drawings can slow the map. B42 multiplayer is reported; no separate B42.21 confirmation was found. A comment reports conflict with Project Writing.

## 13 Better Generator Info

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3576056135) · Workshop `3576056135` · Mod `BetterGeneratorInfo`

Shows generator runtime and highlights powered areas. Other generator-window replacements may conflict. Recent reports mention UI errors and missing values. An old recommendation to disable `DoLuaChecksum` is no longer needed after a game fix, according to the author; do not apply it automatically. B42 Stable is reported; no B42.21-specific confirmation was found.

## 14 Map Symbols Plus (Hand-drawn)

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3399645148) · Workshop `3399645148` · Mod `MapSymbolsPlusDeonHand`

Adds hand-drawn symbols for places and resources to the map palette. The author recommends Map Symbol Size Slider for resizing; it is required for correct icon sizing on B41 but optional on B42. B41/B42 are reported; no separate multiplayer or B42.21 confirmation was found.

## 15 NeatUI Equipment

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3790656296) · Workshop `3790656296` · Mod `NeatUI_Equipment`

Adds a character equipment panel, drag-and-drop changes, outfit sets and outfit protection/insulation display. Requires [NeatUI Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3508537032) (`3508537032`, `NeatUI_Framework`); load it first. The author reports integration with CleanUI, Inventory Tetris and other Neat mods. Saved-outfit changes and synchronization have not been verified; a player report notes increased network traffic with many saved outfits.

## 16 Better Clothing Info

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3604080281) · Workshop `3604080281` · Mod `EURY_CLOTHINGINFO` · Author: Eurymachus

Compares clothing protection, condition, holes and insulation with equipped items; number/bar displays and comparison key are configurable. Toolkit delegates clothing content and comparison to BCI while measuring and placing the complete window. It also restores the native per-item “No Recipes” marker missing from BCI's copied header. Comparison, marker set/clear and menu/controller/anchored placement were checked in isolated macOS SP with the selected B42.21 set; other BCI options were not exhaustively checked.

## 17 Rain Cleans Blood

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=2956146279) · Workshop `2956146279` · Mod `RainCleansBlood` · Author: Akamir

Rain and snow clean blood from the world, clothing and vehicles; ash and animal droppings can be enabled separately. Cleanup types, speed and weather threshold are configurable. By default it works only outdoors during sufficiently heavy precipitation. No required dependencies are listed. Natural-rain cleanup, vehicle-blood cleanup and re-equipping have not been verified on B42.21; recent reports describe problems, but neither cause is confirmed.

## 18 Research indicator: Toolkit

Toolkit marks items with recipes the current character can research, using native knowledge and skill requirements. The separate `HasResearch` mod (`3567695139`) is no longer selected; disable it when updating.

## 19 Neat Building

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3536052310) · Workshop `3536052310`

The selected `Neat_Building_UIOnly` variant changes the building interface without adding structures. Requires [NeatUI Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3508537032) (`3508537032`, `NeatUI_Framework`); load Framework first. Do not enable the structures variant `Neat_Building` together with modular building variants. UI Only does not add building entities; if the world previously used the structures variant, follow its Safe Uninstall Support instructions before switching.

## 20 Eat Smart

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3456212729) · Workshop `3456212729`

The selected `EatSmartInt` variant adds exact-quantity eating actions to the normal Eat / Open and Eat menu. Only one variant may be enabled; `EatSmart` provides a separate submenu if Integrated conflicts. The author recommends loading Integrated above Drink Smart. No dependencies are listed. B41.78 and B42.12.3–B42.21+ are reported; version 2.2.7 includes a B42.21 compatibility update.

## 21 Drink Smart

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3447775367) · Workshop `3447775367` · Mod `Drink_Smart`

Adds a 0% Thirst action and optional litre display/Sip action; it changes manual drinking, not automatic drinking. No dependencies are required. Load after `EatSmartInt` when using Eat Smart Integrated. Version 1.6.10 includes B42.21 fixes for Sip and quantity display.

## 22 Washing Menus Improved

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3460812542) · Workshop `3460812542` · Mod `WashFix`

Improves washing clothes and cleaning bandages, including items in worn bags; shows water/soap requirements and returns items afterward. No required dependencies are listed. It adds no persistent world data. Other changes to water-source menus, washing and transfers require combined testing.

## 23 Neat Crafting & Neat Building - XP & Mod Display

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3540503606) · Workshop `3540503606`

Displays recipe/building XP, related skill and source mod without changing XP awarded. Selected modules are `Neat_Crafting_AddonXP` and `Neat_Building_AddonXP`. Requires NeatUI Framework, Neat Crafting and Neat Building UI Only; load the framework, main mods, then corresponding add-ons. The Building add-on supports UI Only. The description lists B42.12–B42.20.x; the add-ons have not been checked with B42.21.

## 24 Smart Radial Menu

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3494108029) · Workshop `3494108029` · Mod `SmartRadialMenu`

Quick-action radial menu with gamepad, Steam Deck and split-screen support. Integrates with Eat Smart, Drink Smart and Tidy Up Meister; these are optional integrations, not dependencies. Use the B42 Stable variant, not the older Unstable branch. The author expected multiplayer support but had not tested it; B42.21 combination remains unverified.

## 25 Wash Or Rot

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3674907249) · Workshop `3674907249` · Mod `WashOrRot_MP`

Adds hygiene-related dirt, itching, pain and illness risk; mechanics are configurable in Sandbox settings. Use the B42 variant, not `Wash Or Rot / Legacy B42.12.3`. Requires [Moodle Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3396446795) (`3396446795`, `MoodleFramework`); load it first. B42.12–B42.20 is reported; B42.21 is unconfirmed. Other hygiene and body-cleaning mods, including Rain Cleans Blood, may affect the result.

## 26 Gas Pump Indicator

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3755993986) · Workshop `3755993986` · Mod `GasPumpIndicator`

Shows a light for pump power and fuel state. Draws locally from server data and does not change world state; before fuel is known, the light may remain off until a pump is used or the area is reloaded. No dependencies are listed. B42 and built-in co-op host are reported; separate B42.21 combination is unverified.

## 27 Mini Health Plus

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3710913197) · Workshop `3710913197` · Mod `MiniHealthPlus`

Compact injury and bandage panel with optional muscle strain, treatment actions and configurable prompts. No required dependencies; Better Character Info is needed only for optional avatar integration. B42.16–B42.20 is reported; B42.21 has not been checked. Russian translation is available.

## 28 CleanUI

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3437629766) · Workshop `3437629766` · Mod `CleanUI`

Compact inventory/loot windows with search, quick transfers and configurable layout. Toolkit supplies capacity/magazine indicators and expanded Item Details; do not enable their separate Workshop mods. Requires [NeatUI Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3508537032) (`3508537032`, `NeatUI_Framework`); load Framework first. The author lists compatibility with Proximity Inventory; other inventory replacements may conflict.

## 29 The Shortcut

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3470659758) · Workshop `3470659758` · Mod `TheShortcut`

Configurable quick-action panel for items and crafting/building recipes. Tab toggles it by default; mouse wheel changes pages. Requires [NeatUI Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3508537032) (`3508537032`, `NeatUI_Framework`); load Framework first. Gamepad controls are absent and large panels may affect FPS. The author lists version `1.2.18` for B42.21; compatibility with CleanUI, Neat Crafting and Neat Building is unconfirmed.

## 30 TV & Radio ReInvented

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3420581050) · Workshop `3420581050` · Mod `TVRadio_ReInvented`

Reworks TV, radio, car stereo, walkie-talkie and CD interfaces and adds channel videos/VHS. B41/B42 are reported. Toolkit handles device recognition and adds VHS controls; see [TV & Radio ReInvented](docs/FEATURES.md#tv--radio-reinvented). The separate [42.20 fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3796050675) (`3796050675`, `TVRadioReinventedFix4220`) is no longer required with the current Toolkit.

## 31 Planting information: Toolkit

Toolkit displays known planting seasons on seeds and full packets, plus water requirements, growth time and planting months in tooltips. It reads native farming definitions; empty packets and unknown seasons have no indicator. `PlantGrowingSeasons` controls availability. Settings are under **Options > Mods > Toolkit: Planting information**, preserving previous preferences. Disable the separate `SeedSeasonIndicator` mod (`3734639991`); its code and assets are not included.

## 32 organizedCategories

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3370707195) · Workshop `3370707195` · Mod `organizedCategories_core`

Splits broad item categories and supports UI changes, CleanUI, pinning, renaming and container assignment. Load last; do not enable another classifier. Keep built-in Loot Safety enabled to preserve original loot types for ScriptItems. Full mod folder is required. Local distribution requires the same version for all players; local copies need manual updates.

## 33 Transfer a Specified Quantity: Toolkit

Toolkit provides **Grab amount / Put amount** via the native number-entry window. See [quantity transfers](docs/FEATURES.md#bulk-actions). The former [Take Any Amount B42MP](https://steamcommunity.com/sharedfiles/filedetails/?id=3389115640) (`TakeAnyAmount`) is not required.

## 34 Medicine Indicators: Toolkit + Moodle Framework

Toolkit provides eight medicine indicators using the selected Moodle Framework (`3396446795`, `MoodleFramework`). See [medicine indicators](docs/FEATURES.md#medicine-indicators). The old [Medicine Moodles B42.20 port](https://steamcommunity.com/sharedfiles/filedetails/?id=3778856579) (`MedicineMoodlesB42`) is not required.

## 35 Realistic Dashboard & Gauges

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3635591071) · Workshop `3635591071` · Mod `RealisticDash`

Dashboard controls cover windows, locks, radio, air conditioning, seat selection and sleep. No external library is reported. Load before Navigator. Passenger dashboard and other vehicle types have not been verified. Toolkit dashboard integration is documented under [Navigator](docs/FEATURES.md#navigator).

## 36 Navigator

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3708816224) · Workshop `3708816224` · Mod `Navigator`

Plans road routes and provides turn prompts; requires the mod's Navigator or Navigator Micro radio. No external library is reported. Load after Realistic Dashboard (`RealisticDash;Navigator`) and before `organizedCategories_core`. Voice, long drives, rerouting, custom maps and other vehicle mods remain unverified. Toolkit dashboard integration is documented under [Navigator](docs/FEATURES.md#navigator). The separate TheShortcut panel can overlap the dashboard.

## 37 Toolkit Action Queues and Context Menus

Toolkit action queue, bulk actions and context-menu grouping/rules are described under [bulk actions](docs/FEATURES.md#bulk-actions), [context menus](docs/FEATURES.md#context-menus) and [action queue](docs/FEATURES.md#action-queue). Crafting-plan behavior and limits are in [crafting plans](docs/FEATURES.md#crafting-plans).

## 38 Survivor Wishlist

Survivor Wishlist usage, settings, persistence and multiplayer behavior are documented in [Survivor Wishlist](docs/FEATURES.md#survivor-wishlist). No Workshop item is required; install the prepared repository mod on server and clients.

## 39 Toolkit Java Patches

Toolkit Java Patches v0.1.15 patches B42.21 client vehicle/zombie behavior, server media/build acknowledgements and the reproduced vehicle ownership handoff race. It also includes animal/equipment, hutch, native string-property and fluid-name guards. It is experimental; unrelated causes of persistent vehicle desync remain outside the confirmed fix. Follow the canonical [Java Patches build and installation guide](JavaPatches/README.md), including the [optional vehicle diagnostic flag](JavaPatches/README.md#vehicle-authority-recovery-and-diagnostic-logs); ZombieBuddy 2.3.4+ is required on server and clients. The separately published [MP Vanilla Animal Trailer Sync Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3801615436) (`3801615436`, `AnimalTrailerSyncMPFix`) addresses the server's one-animal-per-update timer issue and requires JAR approval when prompted.

## 40 SaucedCarts, SaucedWheelbarrow and Wheelbarrow Craft

Load in this order:

| Mod | Workshop ID | Mod ID |
|---|---:|---|
| [SaucedCarts - Pushable Carts](https://steamcommunity.com/sharedfiles/filedetails/?id=3651954650) | `3651954650` | `SaucedCarts` |
| [SaucedWheelbarrow](https://steamcommunity.com/sharedfiles/filedetails/?id=3689975894) | `3689975894` | `saucedwheelbarrow` |
| [Sauced Wheelbarrow Craft](https://steamcommunity.com/sharedfiles/filedetails/?id=3695168970) | `3695168970` | `saucedwheelbarrow_Craft` |

SaucedCarts adds pushable shopping carts; SaucedWheelbarrow adds wooden/metal wheelbarrows; Craft adds recipes and requires both preceding mods. Both wheelbarrow recipes require Welding 3, welding mask, pipes and blowtorch fuel; wooden also requires three planks, metal a metal sheet. Preserve the complete mod folder. Wheelbarrows share outdoor spawns with carts; default weights are equal, and natural spawns occur only in unexplored areas. SaucedCarts conflicts with `TMC_Trolley`. Tidy Up Meister may leave a cart on the ground after a tool action; use Push Cart again. Toolkit integration details are in [SaucedCarts](docs/FEATURES.md#saucedcarts).

## 41 Zombie Visibility Fix + Stair-O-Vision

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3814073243) · Workshop `3814073243` · Mod `ZombieVisibilityFix`

Reveals qualifying zombies hidden by B42 viewcone visibility; Stair-O-Vision is included and separately configurable. No ZombieBuddy or Java patch is required. The server must include the mod although its logic runs on clients; keep files matched. Defaults leave the toggle unbound and enable sub-tile precision, stair visibility and zombie vision; Hard Mode defaults off. Compatibility with Peek a View's stair rendering has not been checked.

## 42 Plumbed Sink Mains Water Fix

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3764655475) · Workshop `3764655475` · Mod `PlumbedSinkMainsFix`

Restores mains water to moved/plumbed fixtures before shutoff, then uses reserve and overhead-container supply. Official package `1.3`; no dependencies or Java loader. Both server and clients need the mod. The author warns fixtures may need re-plumbing after removal following water shutoff. It does not pool multiple rain collectors or add pipes. Native behavior and multiplayer operation have not been verified.

## 44 Nepenthe's High Beams

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3438126404) · Workshop `3438126404` · Mod `NepHighBeams`

Adds toggleable high beams through `.` or the vehicle radial menu. Options > Mods > High Beams configures the key, distance and intensity; toggle high beams off/on after changing settings. The official package includes a `42.15` variant selected by B42.21: default distance multiplier 1.5, intensity multiplier 2, Always On off. Unlike older descriptions, this variant has no separate surrounding-glow setting. It uses native Mod Options and needs no Java patch or extra dependency. Do not combine with BrighterHeadlights, NepHighBeams2 or NepHighBeams2Java. The author allows adding/removing mid-save; upstream reports describe client-only lighting, so remote passenger synchronization remains unverified. A complete local copy requires manual updates; keep server/client copies matched and avoid a duplicate Steam/local installation. Native B42.21 macOS SP and one-driver Host comparisons confirmed low/high ranges and reverse coexistence on an open road; no separate surrounding glow was observed. Remote passenger synchronization was not tested.

## 45 Reverse Drive Lights

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3798872822) · Workshop `3798872822` · Mod `ReverseDriveLights`

Official package version 4, B42.21. Adds white rear beams only for the local driver while the native transmission is R, headlights are on and the battery has charge; restores short red rear lights afterwards. Current client code changes only rear light parts, complementing NepHighBeams' front lights. No dependencies or Java patch are required. Older README/shared fill-light constants do not establish an active surrounding-glow feature; actual runtime behavior must be checked. Avoid other rear-light replacements because restoration uses fixed vanilla parameters. The local installed copy requires manual updates; keep server/client files matched. Native B42.21 macOS SP and Host verified real R activation, both white rear beams, coexistence with high beams and restoration of both red rear lights. The Host visual control used Pitch Black, 02:00 and the new moon on 20 July 1993; without headlights the world was black. Native driving vision turns rearward while reversing and can hide the forward beam despite unchanged front lamp parameters. Remote passenger visibility was not tested.

## Included Quartermaster

Toolkit includes the complete Quartermaster `0.24.0` feature set: container sorting, category/item/tag rules, presets, priorities, overflow, crafting and the single-player storage manifest. Use **Configure sorting...** on a world container and **Distribute Loot** in inventory/loot controls. Existing designations, global presets and options keep their original storage names.

The separate Workshop item `3761216758` and Mod ID `Quartermaster` are no longer selected. Disable the external mod and remove any overriding local copy when installing the updated Toolkit; keep its save data. Load Toolkit before `organizedCategories_core` and do not add bridge `3797594072`. Multiplayer designations/presets remain shared; the storage manifest remains single-player. Queue adapters retain their supported crafting/manifest boundaries and conservative restrictions on unsupported actions. See [installation](MOD_INSTALL.md#update-the-set) and [action queue](docs/FEATURES.md#action-queue).

## 46 Vanilla Vehicles Animated

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3281755175) · Workshop `3281755175` · Mod `VanillaVehiclesAnimated`

Reworks vanilla vehicle models into separate animated parts: doors, hoods and trunks can visibly open, and removed panels disappear instead of remaining gray. The author reports B42.21 support and allows adding/removing it on existing saves. Only the main mod is selected; transparent windows, passenger-hiding, armor patches and other optional submods remain disabled. Vehicles with independent modded models need their own support.

Selected before Animated Vehicle Parts Fix, Vehicle Aim Roof Fix and the lighting mods. VVA exposes standing vanilla aim poses inside vehicles; the selected [Vehicle Aim Roof Fix](#53-vehicle-aim-roof-fix) targets that symptom while keeping occupants visible. In single-player, leaving a running vehicle far enough away to unload it can collapse its animated parts when returning; the related fix below targets this bug. For multiplayer, VVA alone does not continuously synchronize animations to other players. Its recommended `VASinked` addon is not selected because its author warns of B42.20 incompatibility and users report B42.21 failure. Native macOS SP visuals, compatibility with Toolkit controls/lighting and Host owner/passenger animation visibility have not been verified.

## 47 Animated Vehicle Parts Fix

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3802266453) · Workshop `3802266453` · Mod `AnimatedVehiclePartsFix`

Java fix for animated vehicle parts collapsing into the vehicle center after a running vehicle unloads/reloads. It also addresses missing-part ghost rendering and lights after chunk reload; it supplies no animated vehicle models itself. Requires the selected ZombieBuddy loader and saved client JAR approval. Selected after ZombieBuddy and Vanilla Vehicles Animated. [Source version 1.2.2](https://github.com/MeowWoem/PZMods-AnimatedVehiclePartsFix/blob/ade01e5b0e84128788129d9c90cd61e6a5fd991d/Sources/Java/src/io/ameno/AVPF/Patch_BaseVehicle.java) patches `BaseVehicle.adoptParts` without an SP/MP guard and rebuilds the native light list; it does not set beam intensity or range. VVA replaces vehicle models, so Toolkit light-anchor alignment still needs an in-game check. The author describes the affected bug as single-player only and says the fix is unnecessary in Host multiplayer; selecting it does not establish multiplayer animation synchronization. Native B42.21 macOS behavior and coexistence with Toolkit Java Patches, High Beams and Reverse Drive Lights have not been verified.

## 48 Archery Nexus + Wilderness Progression

Load the base mod before its companion:

| Mod | Workshop ID | Mod ID |
|---|---:|---|
| [Archery Nexus](https://steamcommunity.com/sharedfiles/filedetails/?id=3617854007) | `3617854007` | `ArcheryNexus` |
| [Wilderness Progression: Archery Nexus](https://steamcommunity.com/sharedfiles/filedetails/?id=3776221203) | `3776221203` | `WildernessProgressionArcheryNexusCompanion` |

The companion preserves the base bow, visuals and sounds while adding a dedicated Archery skill, books, starting traits and practice targets. Stone, bone and iron arrowheads use knapping, carving and forging; recovered arrows retain material and condition, can break and can be dismantled for components. Bowstrings wear separately and can be replaced. Archery and Strength affect performance; Maintenance and Archery reduce wear. Drawing drains Endurance and builds arm strain; pain and exhaustion weaken shots and can force release. Nocking is automatic, with manual arrow selection and equipped-quiver priority.

Baseline sandbox settings under Wilderness Progression are damage/range multipliers `1`, Endurance Drain `Normal` and Muscle Strain `Normal`. Increased Bow Hit Chance and plastic-bottle fletching default on; these are upstream defaults, not settings supplied by the selected INI. Keep the existing world's sandbox settings unless deliberately changing them.

Requires both Workshop items on Host and clients. Do not combine the companion with Archery Nexus Fixed or Lite; do not add RadArchery or the RadBows Upgrade as dependencies. As checked on 20 October 2026, the companion was updated on 15 October, but its author explicitly says multiplayer live testing is incomplete. B42.21 full-pack/Host behavior, hunting, arrow conservation and Toolkit queue/crafting integrations have not been verified. Before installing into a gameplay world, use a disposable profile to check crafting, nocking/firing, hit/miss recovery, breakage, restringing, unequipping and Host synchronization. See [installation](MOD_INSTALL.md#archery).

## 49 Detailed Skill Tooltips

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242) · Workshop `3572846242` · Mod `EURY_DST`

Adds per-level numerical bonuses and optional recipe/buildable unlock lists to skill tooltips, without changing XP rates or balance. Recipe/buildable sections and list limits are configurable in Mod Options. This complements the selected Detailed Descriptions for Occupations and Traits; the author explicitly confirms they provide different features and can coexist.

The author declares B42.x support; no required dependencies are listed. Mods replacing skill tooltips may need load-order adjustments. B42.21 full-pack SP/Host behavior, translated numerical descriptions and custom Archery skill coverage have not been verified.

## 50 Foraging Tooltip Extended

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3507997225) · Workshop `3507997225` · Mod `Ivmakk_ForagingTooltipExtended`

Breaks down search-radius modifiers from weather, darkness, exhaustion, skills and traits, highlights radius limits and optionally shows the current radius next to the eye icon. Persistent radius display and tooltip value alignment are configurable in Mod Options. No required dependencies are listed; Quick Forage Icon Discard is an optional recommendation and is not selected.

The author declares 42.15+ support and reports testing on 42.20.4 in SP/MP. Other mods replacing the Vision Effectiveness tooltip can conflict. B42.21 full-pack SP/Host behavior has not been verified.

## 51 Custom Light Switch

[Steam Workshop](https://steamcommunity.com/workshop/filedetails/?id=3779343349) · Workshop `3779343349` · Mod `CustomLightSwitch`

Adds buildable and dismantlable wall switches, including lighting for player-built rooms, using lightbulbs and grid/generator power. Switches in the same room share their on/off state. Learn the recipe at Electrical 3, or read the added magazine at Electrical 1. Construction requires a screwdriver, electronics scrap, electric wire and screws; the new switch also needs a bulb. Building/dismantling grants Electrical XP, can wear the screwdriver and only partly returns construction materials, so this adds construction/progression behavior alongside convenience.

No required dependencies are listed. The author declares B42.21+ support and reports SP and live-server multiplayer tests. English, French and Russian are listed. As checked on 21 October 2026, recent Workshop reports describe bulb-insertion and grid-power problems, including a switch still needing a generator before the power shutoff; an author update does not establish resolution in this set. B42.21 full-pack SP/Host construction, lighting, dismantling, Toolkit queue/menu integration and second-player synchronization have not been verified. Existing world settings are unchanged by the selected INI.

## 52 Nick's Turn Off Fridges

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3778868211) · Workshop `3778868211` · Mod `NicksTurnOffFridges`

Adds right-click unplug/replug controls for fridges and freezers to stop cooling and avoid unnecessary generator demand. The character walks to the appliance. Optional Auto-Unplug is configured per appliance; manually plugging or unplugging it disables that appliance's auto mode. Existing appliances and settings are not changed by the selected INI.

No required dependencies or special load order are listed. The author declares Build 42 single-player and co-op support and allows adding the mod to existing saves; B42.21 is not separately confirmed. Modded appliances using standard fridge/freezer container types are supported according to the author. Workshop reports mention fridge-light performance and an Open All Containers sprite conflict; neither is verified with this set, and Open All Containers is not selected. Full-pack macOS B42.21 SP/Host cooling, generator demand, reload persistence and synchronization remain unverified.

**Before removing the mod, plug every fridge and freezer back in.** The unplugged state is stored on each appliance. According to the author, removing the mod while it is unplugged leaves it inert, without cooling or power demand, until the mod is restored.

## 53 Vehicle Aim Roof Fix

[Steam Workshop](https://steamcommunity.com/workshop/filedetails/?id=3781616141) · Workshop `3781616141` · Mod `CarRoofFix`

Keeps the visible character seated when holding right mouse to look around or aim inside a vehicle. Selected after `VanillaVehiclesAnimated;AnimatedVehiclePartsFix`, before the lighting mods; `VVA_cullseats` stays disabled so occupants remain visible. The downloaded B42 layer overrides ten vehicle aim nodes and the seat-switch node with `Bob_IdleDriving`; it contains no Lua, Java JAR or item/vehicle scripts and declares no dependencies. The B42.21 `aim_heavy`, `aim_spear` and `aim_chainsaw` nodes are not overridden, so this selection does not establish coverage for every equipped weapon.

The author declares B42 SP/MP support and existing-save compatibility. Multiplayer can occasionally need a restart for animation loading; the author's optional Vehicle Enter/Exit Fix recommendation is not selected. Full-pack macOS B42.21 SP/Host RMB look-around, release, seat switching, armed aiming and second-player presentation remain unverified. Workshop supplies the mod directly; no files are repacked into Toolkit.
