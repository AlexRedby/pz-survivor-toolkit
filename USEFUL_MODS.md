# Useful Mods and Settings for Project Zomboid

Catalog of the selected mods, required local components, and related settings. Workshop descriptions and player reports below come from the dated research already recorded here; they are not a fresh review of every Workshop release.

**Installation:** [combined server and client instructions](MOD_INSTALL.md), including the selected INI, dependency order, client/server ZombieBuddy setup, and preparation of all three local mods.

**Current selection:** 49 Mod IDs / 45 Workshop IDs, including all three required repository mods: PZ Survivor Toolkit v0.1.51, Survivor Wishlist v0.1.0 and Toolkit Java Patches v0.1.5. The complete set targets B42.21; the Java component requires ZombieBuddy 2.3.4+ in clients and the server. `tools/prepare_install.py` builds and stages the three folders for distribution. Toolkit now provides its own specified-quantity transfer, medicine indicators, and TV & Radio ReInvented fixes, replacing the removed Take Any Amount (`TakeAnyAmount`), Medicine Moodles (`MedicineMoodlesB42`), and TV translation-fix (`TVRadioReinventedFix4220`) alternatives. Better Containers replaced Proximity Inventory, and Manage Containers was removed. These alternatives are not current requirements. Historical checks below retain their original dates, versions, and counts; see the [README](README.md) for current implementation and checks.

Toolkit v0.1.43 passed 10 native B42.21 single-player checks and 12 checks per multiplayer client with all 45 selected Mod IDs. Checks covered recursive generator repair, cancellation with exact scrap/XP preservation, returning a borrowed book to its wooden cart, waiting cart reorder/cancel, protected active MP transfers and server audits of exact cargo IDs with no duplicates. Multiplayer used stock action timings, two localhost clients and Lua checksums. These were callback-driven macOS checks; physical input, Windows/Linux, WAN jitter and long sessions remain unverified.

**Historical check, 9 October 2026:** Toolkit v0.1.12 was installed locally. The earlier selection of 38 Mod IDs / 36 Workshop IDs, before the switch to Better Containers, passed two isolated B42.21 macOS multiplayer scenarios with EN/RU clients: 33 checks per client, no failed checks or runtime errors. CCI/CleanUI, item transfers, and VHS were checked; individual features of the other mods and long sessions were not. After Proximity Inventory was replaced and Manage Containers removed, the working Host profile had 22 Mod IDs and the portable set had 38 Mod IDs / 36 Workshop IDs. The current Better Containers entry is section 3.

**Installed on 5 October 2026:** all 15 selected mods, NeatUI Framework, ZombieBuddy, and the then-current PZ Survivor Toolkit. The `Host > SurvivorQoL` profile was created. The combined B42.21 smoke test with two local clients passed: 17 checks each, no failed checks, and 60 seconds of shared play; `DoLuaChecksum=true`.

Load ZombieBuddy first on the server; its agent automatically changes the client load order. Conflicting keys were assigned as follows: F8 — Toolkit, F9 — Peek a View, F10 — Better Containers Proximity Lock, F11 — Better Containers Proximity Toggle, F12 — Corpse Only. MP Fast Forward uses Numpad 0–4. The recorded local setup used local copies, which require manual updates. New Steam servers and clients can download the Workshop set as described in the installation guide; local Toolkit, Wishlist and Java Patches folders still need manual distribution.

## 1 Show VHS Skills in Tooltip

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3716522633)

Shows the skills and recipes taught by a VHS tape in its tooltip. Works with tapes that grant both skill XP and recipes. The author says tape contents are detected automatically.

Selected for its native presentation: information appears in the regular item tooltip, like recipe magazines.

- **Workshop ID:** `3716522633`
- **Mod ID:** `VHSSkillNameInTooltip`
- **Versions:** B41 and B42; the author reports testing on B41.78.19 and B42.20, including multiplayer.
- **Modded tapes:** WYD series support is reported for B42; load after the WYD mods.

The description and author comment were checked on 5 October 2026. Multiplayer testing confirmed that skill and recipe data loads; display of recipes already known by the character was not confirmed.

## 2 MP Fast Forward

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3738738086)

Restores time fast-forward in multiplayer and co-op, making it quicker to wait for dawn, read a book, finish crafting or cooking, and complete other actions.

The speed can require agreement from all online players or be controlled by the administrator for the whole server. Sleeping is not required. According to the author, fast-forward stops automatically if any player moves or a zombie approaches a player. Speeds, control mode, and zombie-check radius are configurable in Sandbox settings.

- **Workshop ID:** `3738738086`
- **Mod ID:** `MPFastForward`
- **Versions:** B42.19 and later are reported.
- **Existing saves:** the author allows adding it to an existing game.

The description and comments were checked on 5 October 2026. Recent reports mention a disappearing interface. On our B42.21 set, agreed fast-forward up to 3x and the return to normal speed were checked on two clients.

## 3 Better Containers

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3586216562)

Combines nearby accessible loot, filters multiple categories, lets players rename containers and change their icons, colours, and order, and opens supported nested bags. Smart Deposit sorts first by matching item type, then category, then an available suitable container; if none is available, the item stays with the player. Manage Containers assignments are not used.

- **Workshop ID:** `3586216562`
- **Mod ID:** `EURY_CONTAINERS`
- **Status:** replaced the original Proximity Inventory on 9 October 2026; Manage Containers was removed from the selection. A complete local BC copy is included in default, `Host > SurvivorQoL`, and the portable INI. Older local folders are kept outside `Zomboid/mods`.
- **Settings:** built-in Advanced Display Categories is disabled; organizedCategories supplies categories and loads last. Nested Containers Player/Loot is enabled, preserving the standard multiplayer restrictions. Keys: F10 — Proximity Lock, F11 — Proximity Toggle, F12 — Corpse Only; Numpad 0–4 remains assigned to MP Fast Forward.
- **CleanUI:** BC does not add a separate search row when CleanUI is active. Current Toolkit owns the category filter and prevents BC from installing a competing category-filter implementation. Use Toolkit's Category header control; CleanUI search still hides nonmatching results. BC's proximity, deposit and container-management features remain available.
- **Multiplayer:** character bags and ordinary bags on the ground work. A bag inside a crate cannot be addressed by the native network protocol, so transfers to and from its contents fail. A deeper nested bag inside a ground bag triggers `ContainerID.set`; disabling the UI protection does not fix it. Supported workaround: pick up the whole bag, work with its contents while carried, then put it back in the crate. Vanilla already adds buttons for bags directly inside accessible vehicle containers; deeper access is limited by the protocol to one item ID.
- **Check:** the then-current set of 38 Mod IDs / 36 Workshop IDs was tested on B42.21 macOS with two EN/RU clients: 10 checks each, no failures. Tests covered organizedCategories classification, multi-filter, supported nesting, absence of old mods/MC buttons, Smart Deposit with server confirmations, and CCI during CleanUI switches. Unsupported transfers and the supported whole-bag workaround were also checked. Long sessions, physical mouse operation, and all BC settings were not checked.

## 4 Clean HotBar

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3461263912)

Improves the hotbar and held-item display: shows weapon durability and sharpness, ammunition, jams, battery charge, and remaining container contents. Slot order, panel size, and transparency are configurable.

- **Workshop ID:** `3461263912`
- **Mod ID:** `CleanHotBar`
- **Versions:** B42.12.3–B42.21.0, single-player, hosted multiplayer, and dedicated servers are reported.
- **Dependencies:** no separate UI framework is required.
- **Compatibility:** conflicts are possible with other mods that replace the hotbar or held-item UI; the author recommends loading it near the end of the list.

For B42.21, the author was still completing full in-game testing; a preliminary code review found no changes necessary.

## 5 Neat Crafting

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3502080466)

Replaces the crafting menu with a more convenient interface: search by recipe, ingredient, and result; filters; alternative material selection; and crafting chains. Shows recipe requirements and results and searches nearby containers.

- **Workshop ID:** `3502080466`
- **Mod ID:** `Neat_Crafting`
- **Versions:** B42.9–B42.21.x, single-player and multiplayer are reported.
- **Dependency:** [NeatUI Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3508537032), Workshop ID `3508537032`, Mod ID `NeatUI_Framework`; load it before Neat Crafting. Add both mods to the server.
- **Compatibility:** the author reports a conflict with `what can i craft` and its add-on; other crafting-menu replacements may also conflict.

**Removing it from an existing world:** after using Neat Crafting, do not simply remove it and reload the world. The author's instructions say to keep the main mod or replace it with Neat Crafting – Safe Uninstall Support, linked in the Workshop description. Do not enable the main mod and Safe Uninstall Support at the same time.

## 6 Project Cook

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3490188370)

Adds a separate cooking window with ingredients from inventory, bags, and nearby containers; a queue for adding ingredients; nutrition information; and controls for nearby stoves. It keeps cooking rules as close to vanilla as possible.

- **Workshop ID:** `3490188370`
- **Mod ID:** `Project_Cook`
- **Versions:** B42.10–B42.21.0, single-player and multiplayer are reported.
- **Dependency:** [NeatUI Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3508537032), Workshop ID `3508537032`, Mod ID `NeatUI_Framework`; load before Project Cook. This is also required by Neat Crafting.
- **Optional:** `Project_Cook_Pixel_Icon_Pack` from the same Workshop subscription changes icons; load it after the main mod if enabled.

Recent player reports mention problems with cooking actions in multiplayer; check it on our server.

## 7 Tidy Up Meister

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=2769706949)

After an action, restores the previous held equipment and returns temporarily removed items to their original bag, container, or ground location. Automatic re-equipping can be disabled in the context menu.

- **Workshop ID:** `2769706949`
- **Mod ID:** `P4TidyUpMeister`
- **Versions:** the author confirms B41/B42 Stable and multiplayer; the B42.20 implementation was reworked.
- **Vanilla overlap:** since B42.8, some automatic returns are built into the game; this mod covers the remaining actions.
- **Compatibility:** unusual actions from other mods may be misidentified, returning items that were meant to stay moved.

## 8 Moodle Descriptions Expanded

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3389003300)

Expands the normal character moodle tooltips: explains the effects of hunger, fatigue, and other moodles, and adds numerical penalties and their severity. These descriptions reflect the author's and translators' interpretation, so values may need rechecking after game updates.

- **Workshop ID:** `3389003300`
- **Mod ID:** `B42MoodleDescriptionsExpanded`
- **Versions:** B42; a recent positive report mentions hosted multiplayer, but the author has not separately confirmed B42.21.
- **Compatibility:** other mods that change the same moodle descriptions may conflict; the author recommends loading after moodle mods.
- **Existing saves:** the author allows adding it to an existing game.

## 9 Detailed Descriptions for Occupations and Traits

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3387957272)

Adds numerical effects, known recipes, and foraging bonuses to occupation and trait descriptions. Works during character creation and in the character information window, keeping the original description in the first lines.

- **Workshop ID:** `3387957272`
- **Mod ID:** `DetailedDescriptionsForOccupationsAndTraits`
- **Versions:** the page is titled `[B42.20]`, but on 1 October the author separately confirmed it works on B42.21.
- **Language:** a Russian translation is available for B42.20.
- **Multiplayer:** no separate author confirmation for multiplayer was found; check it when configuring the server.

## 10 Peek a View

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3710281407)

Improves visibility: walls fade from a greater distance, trees become transparent around the character and in the viewing direction, and the upper floor and its zombies are visible while climbing stairs. Vanilla line-of-sight rules are preserved. Each feature can be disabled separately.

- **Workshop ID:** `3710281407`
- **Mod ID:** `PeekAView`
- **Versions:** the current version requires B42.21 or later; the author tested B42.21.0.
- **Multiplayer:** runs client-side; add Peek a View and its dependency to the server so players can download and enable them.
- **Dependency:** [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853), Workshop ID `3619862853`, Mod ID `ZombieBuddy`. Each player must complete the separate ZombieBuddy setup once, following its instructions; the server does not do this automatically. On first launch, approve loading the PeekAView JAR in the ZombieBuddy prompt.
- **Compatibility:** mods with custom stairs and basements, such as Excavation and Basement Building, may conflict with stair visibility; disable that feature if needed.
- **Existing saves:** the author allows adding and removing it because the mod stores no world data.

Entries 4–10 were added at the user's request on 5 October 2026. Links, descriptions, and available compatibility information were checked; the mods were installed and their combined loading was checked in a B42.21 multiplayer smoke test. Tested features and limitations are listed in each entry.

## 12 Share Map Notes

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3676995511)

Automatically shares map symbols and text notes through the game's native system. Adds synced freehand drawing for shared routes and danger zones. Sharing can be enabled for everyone, only the faction, or safehouse members, or disabled.

- **Workshop ID:** `3676995511`
- **Mod ID:** `PZShareMapNotes`
- **Versions:** B42 multiplayer is reported; updated for B42.20. No separate B42.21 confirmation was found.
- **Existing saves:** the author allows adding it to an existing game.
- **Settings:** a pen is required for drawing and an eraser for erasing by default. Per-player and server drawing limits are available.
- **Compatibility:** a comment reports a conflict with Project Writing.

Do not remove the drawing limits without a reason: the author warns that large numbers of drawings can make the map slow for players.

## 13 Better Generator Info

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3576056135)

Enhances the normal generator information window: shows remaining operating time in days and hours and can convert it to real time based on the length of a game day. Highlights the generator's powered area by floor and, optionally, the combined area of all active generators.

- **Workshop ID:** `3576056135`
- **Mod ID:** `BetterGeneratorInfo`
- **Versions:** the author reports B42 Stable, correct consumption calculations on B42.12+, and use on several servers. No B42.21-specific confirmation was found.
- **Existing saves:** the author allows adding or removing it at any time.
- **Compatibility:** other replacements for the generator information window may conflict.

Recent reports mention UI errors and missing new values; check it on our server. The description retains an old recommendation to disable `DoLuaChecksum` on earlier server versions, but the author says in the comments that this is no longer needed after a game fix; do not apply it automatically.

## 14 Map Symbols Plus (Hand-drawn)

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3399645148)

Adds hand-drawn symbols to the normal map palette: safe and dangerous places, gas pumps, basements, food, ammunition, vehicles, generators, wells, workstations, and animals. Useful for marking places to revisit for supplies.

- **Workshop ID:** `3399645148`
- **Mod ID:** `MapSymbolsPlusDeonHand`
- **Versions:** the page reports B41 and B42; a positive report mentions B42.20 Stable. No separate multiplayer or B42.21 confirmation was found.
- **Optional:** the author recommends Map Symbol Size Slider to resize symbols. For B42, it is a separate optional candidate and is not selected here. On B41, the author says it is required for correct icon sizing.

Entries 12–14 were added at the user's request on 5 October 2026. Workshop descriptions and comments were checked during research; the mods were installed and their combined loading was checked in a B42.21 multiplayer smoke test. Tested features and limitations are listed in each entry.

## 15 NeatUI Equipment

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3790656296)

Adds a panel with a 3D character model and slots for clothing, held items, and belt items. Supports drag-and-drop equipment changes, hiding worn items in the inventory list, and saving outfit sets. When changing sets, it finds items in inventory and nearby accessible containers and shows the outfit's protection and insulation.

- **Workshop ID:** `3790656296`
- **Mod ID:** `NeatUI_Equipment`
- **Versions:** the current page is titled `NeatUI Equipment [42.20]`; opening the panel and wardrobe was tested in B42.21 multiplayer.
- **Dependency:** [NeatUI Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3508537032), Workshop ID `3508537032`, Mod ID `NeatUI_Framework`; already in our dependency list, load it before NeatUI Equipment.
- **Compatibility:** the author reports integration with CleanUI, Inventory Tetris, and other Neat mods. Combined loading and opening the panel and wardrobe were tested in our multiplayer smoke test; changing saved outfits was not tested.
- **Multiplayer:** the code runs client-side. A recent report describes use on a B42 dedicated server and increased network traffic with many saved outfits; this is a player report, not a result confirmed by us.

Added at the user's request on 5 October 2026. The description and comments were checked; the mod was installed; panel and wardrobe opening were tested on two B42.21 clients.

## 16 Better Clothing Info

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3604080281)

Replaces clothing tooltips and compares its stats with equipped items, including protection, condition, holes, insulation, and other values. Number and bar displays are configurable; comparisons can be shown only while holding a chosen key.

- **Author:** Eurymachus.
- **Workshop ID:** `3604080281`
- **Mod ID:** `EURY_CLOTHINGINFO`
- **Versions:** the author reports B42, including multiplayer; full operation with our B42.21 set was not tested.
- **Compatibility:** replaces clothing tooltips; the author warns of possible conflicts with other mods that change `ISToolTipInv`.

Added at the user's request on 8 October 2026 and included in the selected INI. The Workshop description and downloaded code were reviewed on 7 October. Toolkit's **Show zero protection changes in grey** option makes displayed zero differences neutral; disable it to restore the original comparison colours.

## 17 Rain Cleans Blood

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=2956146279)

Rain and snow gradually wash blood from the ground, walls, floors, clothing, and vehicles. Ash from burned bodies and animal droppings can be enabled separately. Speed, weather threshold, and cleanup types are configurable in Sandbox settings. By default, it does not clean indoors and works only during sufficiently heavy precipitation.

- **Author:** Akamir.
- **Workshop ID:** `2956146279`
- **Mod ID:** `RainCleansBlood`
- **Dependencies:** the downloaded `mod.info` lists no required dependencies.
- **Versions:** the author reports B42.20+ and multiplayer; in the downloaded code, cleanup is performed by the server and clothing changes are sent to clients.
- **Existing saves:** the author allows adding or removing it at any time.
- **Limitations:** recent reports mention vehicle-cleaning problems on B42.21 and a separate complaint about re-equipping; these are player reports, not confirmed causes.

Selected on 8 October 2026; the user declined the other five candidates in that group. A local copy was downloaded and installed, then enabled in the general mod list and `Host > SurvivorQoL`. Previous settings were saved in a local backup. The isolated B42.21 smoke test with two clients passed: 20 checks each, no failed checks, and 60 seconds of shared play. Server-side cleanup of skin and clothing and receipt of clothing changes by both clients were checked; `AlwaysClean` was temporarily enabled on the test server only. Natural rain, vehicle blood, and long sessions were not checked.

## 18 Has Research

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3567695139)

Shows whether an item can be researched to learn a recipe, without opening its context menu.

- **Workshop ID:** `3567695139`
- **Mod ID:** `HasResearch`
- **Dependencies:** no required dependencies are listed on the Workshop page.
- **Versions:** B42; reports mention B42.20 Stable and B42.19 multiplayer. It has not been checked with our B42.21 set.

## 19 Neat Building

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3536052310)

Replaces the building menu with searches by structure and material, skill and availability filters, list or grid views, detailed requirements, and saved UI settings.

- **Workshop ID:** `3536052310`
- **Variant for our QoL set:** Neat Building - UI Only, Mod ID `Neat_Building_UIOnly`; changes only the interface and adds no structures.
- **Other variant in the same subscription:** `Neat_Building` adds structures and railings; do not enable it together with modular building variants.
- **Dependency:** [NeatUI Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3508537032), Workshop ID `3508537032`, Mod ID `NeatUI_Framework`; already installed, load before Neat Building.
- **Versions:** the author reports B42.12–B42.21.x, single-player, multiplayer Host, and Dedicated Server.
- **Saves:** UI Only adds no building entities and does not require Safe Uninstall Support. If the world previously used the variant with additional structures, switching to UI Only does not remove the need for the corresponding Safe Uninstall Support.

## 20 Eat Smart

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3456212729)

Lets the player eat only as much as needed to reach a chosen hunger, calorie, or protein level. Preserves normal eating actions and vanilla food values.

- **Workshop ID:** `3456212729`
- **Variant for our set:** Eat Smart - Integrated, Mod ID `EatSmartInt`; actions appear in the normal Eat / Open and Eat menu.
- **Alternative:** Eat Smart - Standard Submenu, Mod ID `EatSmart`; a separate submenu to use if Integrated conflicts.
- Enable only one variant.
- **Load order:** the author recommends loading Integrated above Drink Smart.
- **Dependencies:** no required dependencies are listed on the Workshop page.
- **Versions:** the author reports B41.78 and B42.12.3–B42.21+, single-player, multiplayer Host, and Dedicated Server. Version 2.2.7 received a B42.21 compatibility check on 2 October.

## 21 Drink Smart

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3447775367)

Adds a “0% Thirst” action that drinks the exact amount of liquid needed to quench thirst. Optionally shows consumption in litres and adds a small Sip action. Changes manual drinking actions; it does not fix automatic drinking.

- **Workshop ID:** `3447775367`
- **Mod ID:** `Drink_Smart`
- **Dependencies:** the author explicitly states that no dependencies are required.
- **Load order:** load after `EatSmartInt` when using Integrated.
- **Versions:** B42, single-player/multiplayer. Version 1.6.10 from 2 October includes a B42.21 compatibility check and fixes for Sip and quantity display.

## 22 Washing Menus Improved

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3460812542)

Improves washing clothes and cleaning bandages at water sources. Works with items in worn bags and returns them afterward, and shows water and soap requirements. If water is limited, it washes as many items as possible.

- **Workshop ID:** `3460812542`
- **Mod ID:** `WashFix`
- **Dependencies:** no required dependencies are listed on the Workshop page.
- **Versions:** the author reports B42.12.3–B42.21.0, single-player, and multiplayer Host testing.
- **Saves:** the author allows adding or removing it in an existing game; it adds no items, recipes, or persistent world data.
- **Compatibility:** other changes to water-source menus, washing, and item transfers require combined testing.

## 23 Neat Crafting & Neat Building - XP & Mod Display

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3540503606)

Shows XP for a recipe or building, the related skill, and the source mod. Provides base and calculated XP modes with multipliers, plus filters for recipes that grant XP and recipes from mods. It does not change the XP awarded.

- **Workshop ID:** `3540503606` — one subscription for both add-ons.
- **Modules for our set:** `Neat_Crafting_AddonXP` and `Neat_Building_AddonXP`; enable both with their respective main mods.
- **Dependencies:** NeatUI Framework `3508537032` / `NeatUI_Framework`, Neat Crafting `3502080466` / `Neat_Crafting`, and Neat Building `3536052310` / `Neat_Building_UIOnly`. Framework and Crafting are already installed. The Building add-on supports UI Only.
- **Load order:** Framework, the Neat Crafting and Neat Building main mods, then the corresponding XP add-ons.
- **Versions:** the description lists B42.12–B42.20.x and multiplayer Host/Dedicated settings. The add-ons have not been checked with our B42.21 set.

## 24 Smart Radial Menu

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3494108029)

Radial menu for quick item actions. Supports gamepads, Steam Deck, and split-screen. Integrates with Eat Smart, Drink Smart, and Tidy Up Meister; the regular context menu remains available.

- **Workshop ID:** `3494108029`
- **Mod ID:** `SmartRadialMenu`
- **Variant:** B42 Stable; do not choose the older separate Unstable branch.
- **Dependencies:** no required dependencies are listed on the Workshop page; Eat/Drink Smart are compatible add-ons, not requirements.
- **Multiplayer:** the author expects it to work in multiplayer but noted in an August 3 comment that they had not tested it. B42.21 and combined use with our set need checking.

## 25 Wash Or Rot

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3674907249)

Adds consequences for poor hygiene: dirt and blood transfer from clothing to the body, causing the Grimed state, itching, minor pain, and a risk of illness at high levels of dirt. Mechanics and severity are configurable in Sandbox settings. This is a survival change selected alongside QoL mods.

- **Workshop ID:** `3674907249`
- **Mod ID:** `WashOrRot_MP`
- **Variant:** supported B42 single-player/multiplayer version; do not enable it together with the old Wash Or Rot / Legacy B42.12.3.
- **Dependency:** [Moodle Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3396446795), Workshop ID `3396446795`, Mod ID `MoodleFramework`; load before Wash Or Rot. This is a separate library, not Moodle Descriptions Expanded.
- **Versions:** the description reports B42.12–B42.20, single-player/multiplayer; on B42.13+ gameplay logic runs on the server. Our test has not confirmed B42.21.
- **Compatibility:** illness, hygiene, and body-cleaning mods may affect the overall result; combined use with the selected Rain Cleans Blood needs checking.

Entries 18–25 were selected by the user on 8 October 2026. They were added to the catalog only: these eight Workshop mods and the new Moodle Framework dependency were not installed or enabled in `Host > SurvivorQoL` as part of that update. At that point, the expanded set had not had a combined multiplayer smoke test. Later 39-mod checks covered combined loading; they did not exercise every feature of these mods. Neat Building's previously proposed QoL variant, UI Only, and Eat Smart's Integrated variant are listed; the XP add-on is selected for both Neat interfaces.

## 26 Gas Pump Indicator

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3755993986)

Shows the gas pump's state with a light on its body: green means power and fuel are available, red means it has power but no fuel, and no light means no power.

- **Workshop ID:** `3755993986`
- **Mod ID:** `GasPumpIndicator`
- **Dependencies:** none.
- **Versions:** the author reports B42 and single-player/multiplayer and tested the built-in co-op host. It has not been separately checked on B42.21 with our set.
- **Multiplayer:** the indicator is drawn locally from server data; the mod does not change world state. Until the server has determined the amount of fuel, the light may stay off despite power; use the pump or reload the area.
- **Existing saves:** the author allows adding or removing it in an existing game.

## 27 Mini Health Plus

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3710913197)

Compact character silhouette shows injuries, bandage state, and optionally muscle strain. Size, position, and showing only when treatment is needed are configurable. Treatment actions are available in the context menu; prompts for removing bandages and checking stitches can be enabled separately.

- **Workshop ID:** `3710913197`
- **Mod ID:** `MiniHealthPlus`
- **Dependencies:** no required dependencies are listed on the Workshop page. Better Character Info is needed only for optional avatar integration; the original Mini Health Panel is not required.
- **Versions:** the author reports single-player/multiplayer support on B42.16–B42.20; our B42.21 setup has not been checked.
- **Language:** a Russian translation is available.
- **Existing saves:** the author allows adding or removing it at any time.

Entries 26–27 were added at the user's request on 8 October 2026. Descriptions and IDs were checked against Workshop. They remain catalog-only: installation, enabling in `Host > SurvivorQoL`, and a combined multiplayer smoke test were not part of that update.

## 28 CleanUI

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3437629766)

Makes inventory and loot windows more compact and convenient with item and category search, quick transfers, and configurable columns, scale, and transparency. Container order can be changed with the mouse and is saved separately for each multiplayer player. A toggle returns to the normal interface.

- **Workshop ID:** `3437629766`
- **Mod ID:** `CleanUI`
- **Dependency:** the existing NeatUI Framework `3508537032` / `NeatUI_Framework`; load before CleanUI.
- **Versions:** the author reports B42.12.3–B42.21.0, single-player/multiplayer. The tested CleanUI version was `2.9.7`.
- **Compatibility:** the author lists tested compatibility with Proximity Inventory. Other inventory-window replacements may conflict.

Selected on 8 October 2026 and added to the portable `SurvivorQoL-selected.ini`. Combined loading with Framework, Container Capacity Indicator, and Toolkit v0.1.3 was checked in a separate B42.21 test game; the indicator fix is described below. The working `Host > SurvivorQoL` profile was not changed. On 9 October, combined loading of all 38 selected Mod IDs and both CleanUI modes was checked in a separate multiplayer scenario with Toolkit v0.1.12.

## 29 Container Capacity Indicator

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3789660055)

Shows coloured fill bars for containers and bags, including bags nested in other containers. Shows four fill segments for some weapon magazines; this can be disabled in the mod settings. It does not change capacity or contents.

- **Workshop ID:** `3789660055`
- **Mod ID:** `ContainerCapacityIndicator`
- **Dependencies:** none; this is client UI.
- **Versions:** the author lists B42.20 and multiplayer. The tested indicator version was `1.2.0`.
- **Status:** included in the portable INI; use Toolkit v0.1.12 to switch CleanUI modes. Required order: `NeatUI_Framework;CleanUI;PZSurvivorToolkit;ContainerCapacityIndicator`.

**Check result, 8 October 2026:** CCI `1.2.0` with CleanUI `2.9.7` offset the equipped-container bar by one row (`31 px`) and left it visible after hiding the Equipped Items section. Toolkit v0.1.3 corrects the calculation using CleanUI's actual rows and icons, including scale. In a separate B42.21 game, expanded/collapsed rows, hidden equipment, 140% scale, and container reordering were checked. Fill indicators followed containers when reordered; no separate button fix was needed for these versions. CCI still controls magazine indicators. On 9 October, Toolkit v0.1.12 passed 15 checks on each EN/RU client with all 38 Mod IDs: bars for items, icons, and buttons; repeated enhanced/vanilla switches; and actual item transfers. No runtime errors occurred during this scenario.

## 30 The Shortcut

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3470659758)

Adds a configurable quick-action panel for items and crafting or building recipes. Frequently used actions can be pinned and launched with a double-click; right-click opens the corresponding regular menu. The panel keeps an item's assignment even when it is temporarily absent from inventory.

- **Workshop ID:** `3470659758`
- **Mod ID:** `TheShortcut`
- **Dependency:** the already selected NeatUI Framework `3508537032` / `NeatUI_Framework`; load before The Shortcut.
- **Versions:** the author reports B42.12.3+ and single-player/multiplayer; the author checked version `1.2.18` for compatibility with the B42.21 branch. It has not been tested in-game with our set.
- **Controls:** Tab shows or hides the panel by default; the mouse wheel switches pages. Key, size, position, and transparency are configurable.
- **Limitations:** gamepad controls are not implemented; large panels may affect FPS. Compatibility with our CleanUI, Neat Crafting, and Neat Building combination needs checking.

Selected on 8 October 2026 and added to the portable `SurvivorQoL-selected.ini`. Installation and changes to the working `Host > SurvivorQoL` profile were not part of that update.

## 31 TV & Radio ReInvented

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3420581050)

Reworks the interfaces for TVs, radios, car stereos, walkie-talkies, and CD players. Click the player slot to select a VHS tape, then start playback with the device button. Adds videos for TV channels and educational VHS tapes.

- **Workshop ID:** `3420581050`
- **Mod ID:** `TVRadio_ReInvented`
- **Versions:** B41/B42 are reported; the author mentioned testing B42.20.3.
- **Toolkit controls, v0.1.8:** clicking an inserted VHS ejects it without an extra menu. An empty slot offers tapes from inventory, bags, and nearby accessible containers; a tape can also be dragged onto the slot. Fully watched tapes for the current character have the same checkmark as in inventory; unfinished tapes have no checkmark and appear first. **Improve VHS controls** is enabled by default in Toolkit settings.
- **Device recognition:** since Toolkit v0.1.20, a narrow adapter is built into Toolkit without copying the whole window. The separate [TVRadio Reinvented – 42.20 FIX](https://steamcommunity.com/sharedfiles/filedetails/?id=3796050675) (`3796050675`, `TVRadioReinventedFix4220`) was removed from the INI and is no longer needed. The main TV mod remains selected.
- **Status:** selected and installed locally on 8 October 2026; the main mod was enabled in `Host > SurvivorQoL`, local default, and the portable INI. The separate fix is no longer part of the current setup. On B42.21, two clients (EN/RU), CleanUI, Toolkit v0.1.4, and CCI were checked: **18 checks each, no failures**. Tests covered the close button, outside clicks, setting toggle, and all 16 videos without the former Workshop-path symlink. That historical test still used the external translation fix; Toolkit now supplies device recognition itself. Video and synced VHS insertion, playback, stopping, and ejection were confirmed. This was a short local multiplayer test; current full-set checks are summarized at the beginning of this catalog.

**Confirmed issues:** the original mod does not select the installed TV's interface when an English server is joined by a Russian client; the former fix corrected this, and current Toolkit handles device recognition internally. The original mod closes its window when clicking outside, including in CleanUI inventory, and hides the close button. Toolkit v0.1.4 restores the close button and keeps the window open; this behavior can be disabled in Toolkit settings. On native macOS, the original video path is incorrect; Toolkit v0.1.4 resolves it using the actual mod folder, so a separate Workshop fix is no longer needed. Video files must be installed with the TV mod.

**Historical Toolkit VHS checks:** v0.1.7 passed a B42.21 scenario with two EN/RU clients, CleanUI, CCI, and Proximity Inventory: **18 checks each, no failures**. Tests covered selecting VHS from a crate, bag, and ground; dragging; one-click ejection; viewing history; stale-selection protection; and server-side tape ownership checks. No lost or duplicated tapes were found. Menu visibility was checked separately with screenshots. In Toolkit v0.1.8, checkmarks for watched tapes and no marks for unfinished tapes passed on EN/RU clients (3 checks each, no failures). On 9 October, the VHS scenario was repeated with Toolkit v0.1.12 and all 38 Mod IDs: 18 checks per client, no failures or runtime errors. Physical mouse/gamepad input and long sessions were not tested.

## 32 Seed Season Indicator

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3734639991)

Shows planting season on seed items: green star means the best month, green circle means suitable, yellow means risky, and red means out of season. Adds planting months, water, and growing time to the tooltip. Uses crop data from the game and mods.

- **Workshop ID:** `3734639991`
- **Mod ID:** `SeedSeasonIndicator`
- **Version:** installed version `1.4.2` for Build 42; no additional dependencies. A Russian translation is available.
- **Requirement:** the character must learn the season information from a seed packet. Seasonal labels are hidden when the Sandbox option `PlantGrowingSeasons` is off.
- **Settings:** `Options > Mods > Seed Season Indicator` controls icons, tooltips, and other options.
- **Status:** local copies were installed on 8 October 2026 and enabled in local default, `Host > SurvivorQoL`, and the portable INI. Installed files were checked against the downloaded copies, along with Lua 5.1 compilation and translation JSON; other Mod IDs and their order were preserved. Combined loading with the full selected set was checked in an isolated B42.21 multiplayer scenario on 9 October; seasonal labels themselves were not checked in that scenario. No Steam subscription was created; update the local copy separately.

## 33 organizedCategories

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3370707195)

Splits broad categories into specific ones, such as food types, tool purposes, and weapon types and calibres. Categories can be changed through the UI; CleanUI is supported, and items are classified automatically without manual definitions. Pinning, renaming, and assigning items to containers can be configured separately.

- **Workshop ID:** `3370707195`
- **Mod ID:** `organizedCategories_core`
- **Dependencies:** no required external libraries; load last. Do not enable another classifier at the same time.
- **Loot generation:** keep built-in Loot Safety enabled. It preserves the original loot type for ScriptItems when a category change would alter that type; organized categories are applied to item instances.
- **Installation:** install the full mod locally at `~/Zomboid/mods/organizedCategoriesCore`; enable it last in default and `Host > SurvivorQoL`. For local installs, give players the same folder; the Workshop ID in the portable INI allows a new Steam server to download the mod and clients to receive it on connection. Update the local copy separately.
- **Historical check, 9 October 2026:** the portable set with 39 Mod IDs loaded on a B42.21 macOS server and two EN/RU clients; 19 checks each, no failures. Tests covered the new categories, Toolkit filter, CleanUI/CCI/Proximity, and Manage Containers transfer after category reassignment with server confirmation. Hammer and TinnedBeans retained their original loot types on the server. Not all settings, sticky items, long sessions, or loot generation rates were checked.


## 34 Transfer a Specified Quantity: Toolkit

The former [Take Any Amount B42MP](https://steamcommunity.com/sharedfiles/filedetails/?id=3389115640) (`TakeAnyAmount`) has been removed from the selected INI. Toolkit v0.1.21 provides **Grab amount / Put amount** using the native number-entry window, with EN/RU translations.

- One positive integer applies to the whole selection, including different stacks; fractional values are rejected.
- Selected instances, character, and destination container are kept until confirmation. Transfers use the game's native queue and network transactions; changed containers, death, and inaccessible items are checked again.
- Favourites, equipped items, and heavy items that the game forces onto the ground are skipped. A rejected transfer stops its own batch without cancelling another client's transaction with the same number. Native One/Half/All actions remain.
- The feature has its own switch. If Take Any Amount is active, Toolkit hides its command and setting to avoid duplicates.

## 35 Medicine Indicators: Toolkit + Moodle Framework

The former [Medicine Moodles B42.20 port](https://steamcommunity.com/sharedfiles/filedetails/?id=3778856579) (`MedicineMoodlesB42`) has been removed from the INI. Toolkit v0.1.21 creates eight indicators through the already selected Moodle Framework (`3396446795`, `MoodleFramework`). It does not copy the port's code.

- Antibiotics, antidepressants, beta blockers, painkillers, and sleeping pills read authoritative server values. Sleeping-pill strength updates after another dose. Indicators hide if fresh responses are missing for over ten seconds; death and character changes reset their state.
- Black Sage and Common Mallow, including dried variants, show the game's remaining pain- and cold-relief effects. The amount can exceed 100% after repeated use; Common Mallow is consumed during a cold.
- Lemongrass/ginger: Lua cannot access the shared native random cooldown. The indicator shows a clearly labelled upper-bound estimate, and only after the server confirms treatment; an ineffective repeat dose does not restart it. The estimate does not survive a reload.
- **Medicine indicators** and **Herbal medicine indicators** are the two grouped Toolkit switches. Turning a group off hides its icons but leaves native medicine effects unchanged. Existing settings survive upgrades.
- The section is hidden without Moodle Framework. If MedicineMoodlesB42 is active, Toolkit disables its indicators and shows one warning to prevent duplicates. The same Toolkit version is required on the server and clients.

## 36 Realistic Dashboard & Gauges

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3635591071)

Reworks the vehicle dashboard with clickable controls for windows, locks, radio, and air conditioning; scaling; and quick seat selection and sleep. Supports several dashboard styles for different vehicles.

- **Workshop ID:** `3635591071`
- **Mod ID:** `RealisticDash`
- **Dependencies:** no required external libraries are reported; load before Navigator.
- **B42.21 multiplayer check:** version 2.0.2. On two clients, the driver's dashboard, radio power, and volume changes using native actions worked. With TV & Radio Reinvented, the combined car-radio window and its volume worked; Clean HotBar and Smart Radial Menu loaded and opened with the dashboard. Navigator plotted a route with this dashboard using load order `RealisticDash;Navigator`.
- **Check limitations:** the passenger dashboard, other vehicle types, and all buttons were not checked. Startup reports `require("Vehicles/VehicleUtils")` in the passenger module, but the tested driver scenario passes.
- **Status:** selected and included in the portable INI; multiplayer checked on 11 October 2026 in isolated profiles. It is not yet installed in the working profile.

## 37 Navigator

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3708816224)

Plans vehicle routes over the road network, shows turns, and recalculates the route after a deviation. Voice prompts are available in Russian and English. A Navigator or Navigator Micro radio is needed to use it in a vehicle; road data is provided for the standard map.

- **Workshop ID:** `3708816224`
- **Mod ID:** `Navigator`
- **Dependencies:** no required external libraries are reported; the installable radio is an item from the mod itself.
- **Load order:** `RealisticDash;Navigator`; the Navigator author explicitly lists this compatibility and order. `organizedCategories_core` remains last in the overall list.
- **B42.21 multiplayer check:** version 2.1.0. On both clients with Realistic Dashboard, the native monitor button, map, route command, route display, and clearing the route on exiting the vehicle worked. RadioRed/HAM recipes loaded; RadioRed was accepted by the native vehicle Radio slot and could be removed in mechanics. The final `ISVehicleDashboard.render` retained the Navigator wrapper; the dashboard conflict was not reproduced.
- **Toolkit UI, v0.1.19:** the original textured Navigator housing, rounded with a raised rim, was made more compact. Its tint and position match the standard dashboard, standard/heavy/sport styles, and black, red, or brown Realistic Dashboard trim. A shared mount uses the lower part of the original texture, with its edge tucked behind the dashboard curve. The map accounts for dashboard size; text and buttons retain their readable native size. Disabling **Fit Navigator to vehicle dashboard** restores the original appearance while preserving routes; the setting is hidden when Navigator is absent.
- **Texture styling check, v0.1.19:** 12 native B42.21 views, including both heavy dashboards, HAM/value radio, 0.75x/1x/1.4x/2x, and returning to 1x. Realistic Dashboard views were tested with the full 42-mod selected set on a separate multiplayer server and one EN client. Route creation and persistence, power button, map/overlay coordinates, dragging, closing, and restoring the original UI passed. Dashboard volume, the TV & Radio Reinvented window, and Smart Radial Menu were also checked. A matching wood tint was chosen; a separate wood texture is not copied. Other dashboard mods and split-screen were not checked.
- **TheShortcut placement:** its separate draggable panel can overlap the dashboard. Move it to a free area with the mouse; Navigator styling does not reposition it automatically.
- **Check limitations:** the test server created the radio and installed it through the native handler; crafting and full removal/reinstallation were not performed. Voice, long drives, rerouting, custom maps, and vehicles were not checked. Workshop reports about crafting and Sandbox settings were not fully resolved by this test.
- **Status:** selected and included in the portable INI; multiplayer checked on 11 October 2026 in isolated profiles. It is not yet installed in the working profile.

## 38 Toolkit Action Queues and Context Menus

PZ Survivor Toolkit includes a native action-queue panel, bulk item actions, and context-menu features. These are part of the local Toolkit copy; they add no Workshop item and are not separate INI requirements.

- **Show action queue** is enabled on fresh profiles and keeps existing saved preferences. Multi-step operations collapse into expandable rows with remaining native-step counts. Dragging moves whole waiting operations; moving one above active reading pauses and resumes the book. Enabled header crosses cancel a whole waiting operation with its preparation and returns; expanded crosses cancel eligible individual steps. Started operations, shared items/world targets and unaudited dependencies remain protected. See [queue controls and limits](README.md#action-queue).
- Four independent options cover **Dismantle selected electronics**, **Remove batteries from selected items**, **Unload selected magazines and firearms**, and **Remove attachments from selected weapons**. They extend the existing context actions and operate on the selected instances, retaining native tools, timing, results and XP where applicable. Favourites and worn/held items are skipped. Surviving devices and tools use native return steps where supported; dismantled items are consumed. Ordinary cancellation or stale targets stop the remaining batch. See [Toolkit controls](README.md#controls) for each action's limits.
- **Group context menu actions** groups known actions across inventory, world, vehicle, and health menus. Short menus stay compact and unknown mod commands remain visible. **Context menu rules** can assign a seen action to a group or main menu, hide it, or restore automatic defaults. Rules are local to each client. Disable the option to restore the original menus; the section is hidden while Context Menu Organizer or its World variant is active.

- **Plan prerequisite crafting** adds an icon-based plan inside Neat Crafting's recipe-details pane, with a separate window for native crafting. It shows total consumed materials, reusable tools and intermediate steps, using reachable materials, exact original item IDs and ordinary game actions. Intermediate surplus is reused; every step rechecks its inputs. Deterministic whole-item recipes are supported; fluids, partial uses and custom callbacks remain ordinary crafting. See [crafting plans and limits](README.md#crafting-plans).

## 39 Survivor Wishlist

The independent `PZSurvivorWishlist` mod is at version 0.1.0, **required and already enabled in `SurvivorQoL-selected.ini`** after the crafting/UI mods. Install it on the server and every client from the prepared set, preserving `common` and `42`. It requires neither Shopping List nor WANTED.

- Provides personal and shared lists with a searchable item catalog. Named players and faction members with access can all edit the same list; only its owner changes access. Desired quantities are shared goals, carried counts are local to each player, and completion is marked manually. Native inventory context menus and native, Neat Crafting, Neat Building, and Project Cook crafting windows can add wanted items. Crafting shows results and missing ingredients; for recipes with alternatives, choose one. Fluids and partial uses represent one suitable item/container, not an exact quantity.
- Highlights wanted inventory rows and visible loose items on the ground within 15 tiles and on the same floor. It does not scan containers, corpses, or contents of bags on the ground. CleanUI inventory modes and Better Containers combined item views are supported. With Toolkit installed, wishlist colours take priority for wanted ground items.
- Open with K or the left sidebar. Options under **Options > Mods > Survivor Wishlist** independently control inventory highlights, ground highlights, crafting controls, colour, and hotkey. Close windows with their native close button or Escape.
- Lists persist on the server under `Zomboid/Lua/PZSurvivorWishlist/`, separated by the encoded save path. Back up this directory with the world and retain the same save path when restoring. Two alternating checked files are used; global ModData is avoided because vanilla clients can request named global tables without wishlist access. Single-player uses the same validation and storage. No item, recipe, or loot content is changed.

Wishlist 0.1.0 passed isolated B42.21 macOS multiplayer checks on two EN/RU clients with Lua checksums enabled: 33 checks per client alongside the 39 selected mods, five checks after a full server/client restart, and 26 checks with only Wishlist installed. Coverage included shared editing, conflicting revisions, invitation/faction revocation, persistence, CleanUI modes, Better Containers, and crafting adapters. A standalone UI pass checked 11 cases per client, including Russian catalog search, native crafting/building layouts, toggles, and repeated window cleanup; screenshots were also inspected. See [README](README.md) for test commands.

## 40 Toolkit Java Patches

The independent `PZToolkitJavaPatches` mod v0.1.5 is required and selected immediately after ZombieBuddy. `tools/prepare_install.py` builds it and includes it alongside Toolkit and Wishlist. It has no Workshop item. Install the same prepared folder on the server and every client; ZombieBuddy 2.3.4+ must load in all those processes. See the [build, Host and dedicated-server guide](JavaPatches/README.md).

It patches B42.21 client zombie-speed decoding, vehicle interpolation recovery and animal-trailer membership, plus the server's stale VHS stop timer and build cancellation acknowledgements. Version 0.1.4 repairs stale client trailer entries after unloading; 0.1.5 prevents an early equipment acknowledgement from clearing the grabbed animal out of the hands; it is already included through the selected Java mod, with no additional Workshop item. See [installation and activation checks](MOD_INSTALL.md#animal-trailer-fix). Target bytecode guards disable unsupported patches. It remains experimental and is not established as a fix for long vehicle freezes or all movement jerks.

[MP Vanilla Animal Trailer Sync Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3801615436) is also required in the selected INI: Workshop `3801615436`, Mod ID `AnimalTrailerSyncMPFix`, verified v1.3 on B42.21 with ZombieBuddy 2.3.4. It fixes the separate server timer bug that synchronizes only one animal per trailer update interval. It complements Toolkit Java Patches' unloading and equipment fixes. Workshop supplies it; approve its JAR if prompted and verify `[AnimalTrailerSyncMPFix] ACTIVE` in the server log. See the [combined installation guide](MOD_INSTALL.md#animal-trailer-fix).

On 12 October 2026, the prepared 41-Mod-ID set passed 33 native wishlist/UI/shared-editing checks per EN/RU client on a macOS dedicated server with Lua checksums enabled. Required Java transformations loaded on the server and both clients; the native vehicle/media build regressions also passed. Ordinary Host launchers, Windows/Linux, every individual mod feature and long sessions remain unverified.

## 41 SaucedCarts, SaucedWheelbarrow and Wheelbarrow Craft

Selected together on 14 October 2026. Load in this order:

| Mod | Workshop ID | Mod ID |
|---|---|---|
| [SaucedCarts - Pushable Carts](https://steamcommunity.com/sharedfiles/filedetails/?id=3651954650) | `3651954650` | `SaucedCarts` |
| [SaucedWheelbarrow](https://steamcommunity.com/sharedfiles/filedetails/?id=3689975894) | `3689975894` | `saucedwheelbarrow` |
| [Sauced Wheelbarrow Craft](https://steamcommunity.com/sharedfiles/filedetails/?id=3695168970) | `3695168970` | `saucedwheelbarrow_Craft` |

SaucedCarts provides pushable shopping carts with storage, wear, repairs and built-in shopping-cart crafting. SaucedWheelbarrow adds wooden and metal wheelbarrows; Craft adds their recipes and requires both preceding mods. Both wheelbarrow recipes require Welding 3, a welding mask, pipes and blowtorch fuel. The wooden version also uses three planks; the metal version uses a metal sheet. The Craft add-on declares its ID and dependencies in `common/mod.info`; preserve the complete mod folder.

Wheelbarrows share outdoor spawns with shopping carts, including parking lots. They do not delete shopping-cart spawns; the default outdoor weights are equal for the three types. Natural cart spawns are limited to unexplored areas. SaucedCarts is incompatible with the original `TMC_Trolley`; do not combine the two frameworks.

Tidy Up Meister can leave the cart on the ground after a tool action. Use Push Cart again; automatic return to pushing is not guaranteed. Installed as unchanged local copies and enabled in the local default and Host SurvivorQoL profiles on 14 October 2026. The portable INI also includes all three. An isolated B42.21 dedicated server with the selected 44-mod set passed 36 checks on each simultaneous EN/RU client: actual wheelbarrow crafting, cart storage/transfers, repeated drop/pickup, exact cargo IDs and server audits. Tidy's normal tool-action restoration left the cart safely on the ground. Those initial checks did not cover save reload or ForceReequip cancellation; later checks below cover them. Local Workshop copies require manual refresh and identical copies on all players.

Toolkit v0.1.37 also initializes the existing SaucedCarts drop, unequip and forced-drop guards on dedicated-server startup. Without this, ordinary server drops bypass wear and stale hand references can duplicate a ground cart and its cargo. After the fix, an isolated two-client B42.21 run passed 28 checks per EN/RU client: both break paths preserved exact cargo IDs (including nested bag contents), normal/admin/instant pickup equipped both hands, and server/client audits found one cart after a stale-reference forced drop. A fresh single-player world also passed 40 checks: both break paths preserved every cargo ID, and 30 full world menus plus recursive shovel lookup passed with empty hands, a held shovel and a shovel stored in a held cart. The reported single-player cargo disappearance, pickup failure and farming exception were not reproduced in these scenarios; no speculative overrides were added. Those v0.1.37 checks did not cover harvest-ready crops or Tidy ForceReequip cancellation.

Toolkit v0.1.40 fixes two additional confirmed cases: Tidy ForceReequip cancellation leaving a ground cart in hand slots, and multiplayer cart pickup/equip invalidating itself after the server has already equipped its exact target. The latter caused Tidy to restore empty hands and leave the cart inventory-only. Client completion recognizes its own started action and exact inventory cart, and successful completion repairs missing hand equipment; SP/server validation is preserved. Stale hand cleanup leaves the cart and cargo on the ground, so use Push Cart again.

Remaining native checks passed 44 harvest checks (30 crop menus and three actual harvests), 10 SP cancellation/save checks and four checks after loading that save in another process. Both carts and nested cargo survived seven accelerated game days and actual chunk unload/reload; an unprotected control item was removed, proving sandbox cleanup ran. The cart adapter also passed a 20-minute dedicated-server soak: 100 pickup/transfer/drop cycles per EN/RU client, exact client/server cart and cargo audits, action queue on/off, and zero failures. The final v0.1.40 combined build passed six focused checks per client after preserving the independent main changes. Windows/Linux, WAN delays and hours-long play remain unverified; only this Mac was available.

## 42 Zombie Visibility Fix + Stair-O-Vision

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3814073243)

Reveals qualifying zombies hidden by B42's inconsistent viewcone visibility. Stair-O-Vision is included in the same mod and can be disabled separately. It does not require ZombieBuddy or a Java patch.

- **Workshop ID:** `3814073243`
- **Mod ID:** `ZombieVisibilityFix`
- **Selection:** included in the portable INI and installed as an unchanged official local copy in the working client and Host profile. True Line of Sight was not selected.
- **Settings:** **Options > Mods > Zombie Visibility Fix**; the toggle key is unbound by default. Enabled, sub-tile precision and stair visibility keep their upstream defaults. Sandbox **ZomVisFix > affect zombie vision** defaults to enabled, allowing revealed zombies to detect the player through native detection rules; Hard Mode defaults to disabled.
- **Multiplayer:** the server must include the mod even though its logic runs on clients. Use matching mod files; the portable INI supplies the Workshop ID for Steam downloads.
- **Installation check, 15 October 2026:** official package metadata, Lua 5.1 compilation, translation JSON and copied-file checksums were checked. Gameplay and compatibility with Peek a View's stair rendering were not tested.

## 43 Plumbed Sink Mains Water Fix

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3764655475)

Restores mains water to moved and plumbed fixtures while the town supply is running. After shutoff, native reserve water and then the overhead-container supply take over. The upstream mod also supplies plumbed fixtures in player-built rooms through its reserve-water workaround.

- **Workshop ID:** `3764655475`
- **Mod ID:** `PlumbedSinkMainsFix`
- **Version:** official package `1.3`; no dependencies or Java loader required.
- **Selection:** included in the portable INI; installed unchanged locally and enabled in the current default and Host SurvivorQoL profiles. Both server and clients need the mod.
- **Installation check, 16 October 2026:** both Lua files loaded and passed a focused fixture check for mains, player-built reserve, shutoff, empty reserve, untouched fixtures, client flag updates, menu cleanup and the plumbing hook. The B42.21 native plumbing action and event names were inspected; installed files match the official package. This is not an in-game or multiplayer verification.
- **Removal:** the author warns that fixtures may need re-plumbing when removing the mod after water shutoff. This mod does not pool multiple rain collectors or add pipes.

## 44 Quartermaster

[Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3761216758)

Designate storage containers for multiple categories or specific item names, then use **Distribute Loot** to haul items to matching containers. Supports presets, destination priorities and overflow to another matching box. This is category/item routing, not arbitrary tag expressions.

- **Workshop ID:** `3761216758`
- **Mod ID:** `Quartermaster`
- **Version:** official package `0.24.0` (beta); no additional dependency or Java loader required.
- **Controls:** right-click a world container and choose **Configure sorting...**. Use **Distribute Loot** in the inventory/loot controls; settings are in **Options > Mods > Quartermaster**.
- **organizedCategories:** the installed Core already includes `zzz_organizedCategories_quartermaster.lua`, which supplies its runtime categories and refreshes source items before sorting. Keep Quartermaster before `organizedCategories_core`. Do not add the older separate bridge `3797594072` on top of this integration.
- **Selection:** installed unchanged locally and enabled in the current default, Host SurvivorQoL and portable INI. Install on the server and clients; multiplayer container designations and presets are shared. The author's storage manifest is single-player only.
- **Installation check, 16 October 2026:** all 24 package Lua files compile and both translation JSON files parse. Copied-file hashes and additive profile changes were checked. A focused fixture using the actual Quartermaster category module and existing organizedCategories adapter passed category discovery, item listing, source stamping, cache refresh and repeated installation checks. This is not a gameplay, CleanUI button or multiplayer compatibility test. Quartermaster's custom actions have no dedicated Toolkit queue adapter. Its manifest also wraps native transfer completion, which can make Toolkit conservatively disable cancellation/reordering for ordinary transfers. Sorting execution and queue integration have not been verified in game.
