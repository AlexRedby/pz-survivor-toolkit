# Features and controls

[Overview](../README.md) · [Installation](../MOD_INSTALL.md) · [Development](DEVELOPMENT.md)

## Contents

- [Controls](#controls)
- [Bulk actions](#bulk-actions)
- [Context menus](#context-menus)
- [Crafting plans](#crafting-plans)
- [Action queue](#action-queue)
- [Survivor Wishlist](#survivor-wishlist)
- [Highlights](#visibility-and-rendering)
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

## Bulk actions

- **Cut selected clothing** adds **One item / Cut selected clothing (N)** inside the native cut/rip submenu when at least two eligible garments are selected. Handles mixed cotton, denim and leather using each item's native recipe; denim/leather require a suitable cutting tool. Only selected instances are consumed; favourites, worn/held items and ineligible clothing are skipped. Supports grouped stacks and reachable containers. Disable it independently in Mod Options.
- **Dismantle selected electronics** extends the native dismantling action with **One item** and **Dismantle selected (N)** when at least two eligible items are selected, including grouped stacks and mixed electronics. Both variants retain the native recipe icon. Flashlights keep their battery action alongside dismantling, with the two dismantling variants in a third-level submenu. Supports the native simple electronics, electronic devices, miscellaneous electronics, power bars and battery-lighter dismantling recipes. Favourites and worn/held items are skipped. Each action binds its selected item explicitly and keeps native tools, duration, outputs and XP; tools from reachable containers are transferred once and returned after the batch. Normal cancellation stops the remaining queue. If another player takes a selected item, the rejected pickup safely stops this batch. Toolkit prevents an already-rejected bulk pickup from cancelling another client's same-numbered transfer; ordinary game actions and manual cancellation keep the native network protocol. Disable this feature in Mod Options to hide the command.
- **Eat selected (N)** appears in the Eat submenu while the action queue is enabled, with full, half and quarter choices where the native menu offers them. It handles selected ready-to-eat food, including herbs and flowers, and the verified native `OpenCannedFood` / `OpenCannedFood2` recipes. Each can opens through native crafting; eating waits for its exact created food ID before returning tools and restoring the mask. Partial portions work in SP and MP. Repeated clicks reserve different selected items; favorites and already queued food are excluded. Missing food or being too full skips affected steps without clearing unrelated work. Group cancellation finishes an ongoing eating/preparation step, stops an unfinished opening recipe and retains already-created food; late results cannot restart eating. A missing server result times out after 30 seconds without recreating or consuming food. Eat Smart, changed callbacks and unverified opening recipes keep their existing commands.
- **Remove batteries from selected items** adds **One item / Remove batteries from selected (N)** to the native Remove Battery recipe. Each selected compatible device keeps its identity, the extracted battery uses the game's native charge conversion, and devices picked up from bags or nearby containers use the native return-to-container action after the batch. This covers the native crafting recipe, not radio power-panel actions.
- **Unload selected magazines and firearms** extends native unloading with **One item / Unload selected (N)**. Supports loose magazines and firearms with integral magazines, including mixed selections. Chambered rounds and magazines inserted into weapons keep their separate native actions.
- **Remove attachments from selected weapons** adds **Remove all parts from selected weapons (N)** beside the existing per-part choices. Uses the native detachable-part checks and tool requirements, preserving each part's identity.
- The dismantling, clothing, battery and weapon bulk features have their own Mod Options switches. They skip favourites and worn/held items at selection, bind exact selected IDs, and stop the remaining queue on cancellation or stale targets. Native weapon callbacks and queue hooks retain Tidy Up Meister's existing transfer and equipment policies when that mod is active; they do not force an additional return to the previous hand item.
- **Grab/Put amount** accepts one positive whole-number budget for the entire selected batch. It captures exact items and destination, rechecks reachability and character identity on confirmation, and uses native transfer actions. Favourites, equipped items and heavy forced-drop objects are skipped. With organizedCategories Stick enabled, a mixed selection also skips stuck items; deliberately selecting one row/stack permits its transfer. The original selection determines that exception even when the requested quantity is one. Rejected pickups stop their own batch without cancelling another client's same-numbered transaction. The independent switch is hidden with TakeAnyAmount active.

## Context menus

**Group context menu actions** groups known actions automatically across native inventory, world, vehicle and health context menus. Categories cover food, equipment, health, crafting, maintenance, devices, transfers, world interaction, vehicles, farming and research. Common actions are ordered before secondary and destructive commands using fixed purpose-based priorities: use/equip/heal/read for carried items, pickup for loot, opening/traversal in the world and entry/control/refuelling for vehicles. This is a curated default, not measured usage or adaptive click tracking. Equal-priority actions keep their native relative order; unknown commands and manual placements remain anchored. Native section titles and portion/recipe selectors retain their structure. Exact repeated commands are shown once, including inside native submenus; actions on different targets or with different arguments, tooltips or metadata remain separate. Each selected-item batch operation appears once, keeping the other native single-item choices. Short menus stay compact; unknown mod commands remain visible. Existing callbacks, icons, tooltips and portion/recipe submenus are preserved. **Context menu rules** in the same Mod Options section lets you search known actions, place an action in a group or the main menu, hide it, or restore automatic defaults. To capture a fresh example and discover new actions, keep the editor open and right-click the item in inventory; its menu becomes the selected example without changing the rule scope. Capture stops when the editor closes and its temporary examples are released. The known-action catalog and saved rules remain available; ordinary menus apply those rules while the editor is closed. Rules are saved locally per client. Disable the feature to restore the original menus immediately. This section is hidden while either Context Menu Organizer or Context Menu Organizer World is active. No additional Workshop mod or change to the selected INI is needed.

Context-menu preferences use the two verified global profile files `Lua/PZSurvivorToolkit_ContextMenus_a.txt` and `Lua/PZSurvivorToolkit_ContextMenus_b.txt`; back up both. The old `PZSurvivorToolkit_ContextMenus.ini` imports automatically and remains unchanged. Later edits require the current Toolkit reader. Failed preference writes roll back the visible edit and show an error in the editor; reopening reloads the verified disk state, including a write that completed before its close/readback failed. An interrupted write retains the previous complete snapshot.

## Crafting plans

Select a recipe in **native crafting** or **Neat Crafting**, then click **Plan crafting**. In Neat Crafting the plan replaces the right-hand recipe details, keeping the recipe list and Wishlist accessible; **< Recipe** returns to the ordinary controls. Native crafting opens a separate plan window. Item icons and quantities show the final result, materials consumed from available stock, reusable tools and ordered intermediate steps. Intermediate ingredients are not counted again as stock requirements. Each step lists its ingredients with **Need / Stock / Make** counts; hover for details. Click an ingredient to choose a material or **Auto**. The choice applies to that ingredient in every use of the same recipe, including prerequisite recipes, and immediately recalculates the whole plan. Choices remain editable if the selected material cannot be obtained.

The quantity is the number of final recipe executions. After changing it, click **Recalculate**, review the result, then **Queue this plan** to add ordinary game actions. If ingredients change before confirmation, review the updated preview and confirm again. Switching recipes or closing Neat Crafting discards its open preview. Disable **Plan prerequisite crafting** in Toolkit Mod Options to hide these controls and restore ordinary crafting immediately.

The planner uses reachable stock, accounts for shared ingredients across the entire chain and reuses intermediate surplus. It respects known recipes, skills, surfaces and workstations. Original item IDs are bound explicitly; favourites and worn/held consumables are excluded. Untouched native auto-filled inputs leave material selection automatic. An explicit native picker choice fixes the material type and prefers the chosen instances first; later repetitions may use other items of that type or newly crafted intermediates. **Auto** in the plan overrides that preference for the current preview. Closing the preview discards its material overrides. Each step checks the actual items again, and tools/books borrowed from containers use native returns. A plan can be cancelled as one operation while waiting or during a supported native crafting step. Remaining dependent steps are removed together; already completed results remain in the inventory.

Planning currently supports deterministic whole-item handcraft recipes. Liquids, partial uses, variable/random outputs, custom recipe callbacks and mixed-type manual inputs stay with ordinary crafting. Generated intermediates must arrive in the character's main inventory; the plan will not take newly appearing shared-container items instead. Search is bounded to 100 craft steps and 32 dependency levels. No materials are reserved on the server: another player's pickup, a broken tool or an ordinary interruption can stop the remaining queue. Project Cook's separate panel and building recipes have no planning control yet.

## Action queue

The movable and resizable **Actions** window shows the game's existing queue, with item/action icons, current progress and mouse-wheel scrolling. It has no five-action limit. It is enabled on fresh profiles; disable **Options > Mods > PZ Survivor Toolkit > Show action queue** to hide it. Existing saved choices are preserved.

- Multi-step operations collapse into a task row, such as **Unload Rounds**, instead of being named after their initial preparation. All 278 native B42.21 action definitions have EN/RU presentation entries, with mode and target labels where available. Completed main steps retain their operation title during returns. Mixed tasks are shown as **Multiple actions**; unknown mod actions retain their type for identification. Click **+** to see each native step or **-** to collapse it. Supported Craft All, native/Neat multicraft and Toolkit bulk tasks show completed/total craft iterations or actions, excluding preparation and returns. Unknown totals show only the completed count. Other tasks show remaining native steps; none of these counts promises a number of output items. The header shows the current step's progress while that operation runs.
- Click an enabled cross on an operation header to cancel its remaining work while keeping unrelated queued actions. Supported active reading, world dismantling, crafting and item repair stop through the native game action; an in-flight pickup, equipment step or audited Toolkit firearm action finishes before its remaining operation is removed. Cancelling a batch also prevents its future native Craft All continuations. Surviving borrowed items return through native transfers when their original container is still reachable; consumed inputs and completed results are never recreated. An inaccessible return leaves the item carried. Shared items and unverified callbacks/dependencies stay protected. Expand an operation to cancel eligible steps individually; crafting and repair crosses cancel their whole operation, including UI state and returns.
- Drag a waiting row or its header to move the complete operation, including preparation and returns. Moving it before active reading pauses the book, performs the moved operation and resumes reading from native saved progress. Native world dismantling can similarly yield to urgent work, then revalidate tools and its target through a fresh native action. Single-player building supports the same interruption. Multiplayer building requires Toolkit Java Patches 0.1.3 on the server: the queue waits for authoritative cancellation before resuming; a build that completed first is never repeated. Servers without this acknowledgement keep active building protected. If no terminal response arrives within 30 seconds, the queue clears without replay. Waiting native building and barricading commands can queue without discarding earlier work. Stove power controls from the native context menu, loot window, oven window, CleanUI and Project Cook request priority automatically. They run at the next safe operation boundary or pause supported reading, then resume it with saved progress. Other queued work keeps its relative order. The request records the desired on/off state, which the server revalidates; another player already reaching that state does not cause a second toggle. Shared dependencies, including transfers that switch a microwave off, keep their order. Washer/dryer toggles and oven settings append normally; their approach is calculated when execution reaches them. A removed appliance is skipped without dropping unrelated work.
- Native handcraft operations can be reordered when their inputs and outputs are known and independent. Pure item recipes with finite future input/output types can also move before their materials are selected, including compatible legacy Craft All. Shared material types, recipe callbacks, fluid/energy inputs, unknown replacement effects and a shared crafting UI keep their order. Selected materials remain native selections, not server reservations. Waiting item repair can cross independent reading, non-inventory radio/TV controls, walking and item transfers; matching future donors and unverified outputs remain protected. Vanilla, Neat Crafting, Project Cook handcraft and native legacy Craft All cancellation preserve batch counters and returns. Fluid operations protect both containers; medical requests protect the wound and future supplies. Unknown actions and modified lifecycle/helpers stay barriers. Use the operation header to cancel independent transfers; preparation and return steps remain protected when edited separately. Hover a disabled control for the reason.

### Supported actions and limits

| Action family | Queue behavior and limits |
|---|---|
| Washing and drying | Independent waiting work can move or cancel. An active step finishes with native soap/water/towel use; missing inputs skip their operation. Shared water, soap, towels and wetness retain order. |
| Medical treatment | Independent wounds and supplies can move; the same wound, future supply types, clothing effects and shared tools retain order. Supported active treatments stop through native cleanup. Missing supplies or unavailable patients stop only their operation. Native menus, first splint drops and reviewed MiniHealthPlus treatments use these contracts. MiniHealthPlus bandage replacement groups removal, pickup and application; cancellation stops remaining stages without undoing completed treatment. Native inventory bandaging supports exact selected items from the main inventory and carried bags, preserving its native wound checks. Unknown producers and world pickup paths remain protected. |
| Carried bags | Independent transfers can move when every destination and ancestor has capacity. Moving/equipping/consuming a containing bag remains a dependency. SP can account for space freed by a prior pickup; MP keeps conservative bounds. Synthetic proximity endpoints and unknown capacity callbacks stay protected. |
| Food with empty dish output | Guaranteed full eating of ordinary food already in the main inventory can move or cancel independently when its one replacement item is proven plain or has exactly one empty native fluid component. The original food cannot be used afterward. Factory callbacks, other or nonempty components, custom/evolved or state-changing food and transfer-capacity prefixes retain protection; native portions, output creation and Host authority are unchanged. |
| Drinking water | Native clean-water drinking preserves following work when its own remaining water reaches zero before the timer or Host completion acknowledgement. Native portions, hydration and duration are unchanged. Nutritious/mixed fluids, world items, changed inputs and unknown callbacks retain their existing protection. |
| Emptying water | Pending native emptying of ordinary carried clean-water containers can move or cancel independently. Drinking from the same bottle and moving its containing bag retain their dependencies. Captured-volume peaks stay within the original full-weight capacity bound; future emptying never supplies capacity credit. Active work, mixtures, world/resource containers and changed callbacks stay protected. |
| Ordinary world storage | Reviewed adjacent crates and shelves support independent leaf-item pickup/return edits within current capacity bounds. SP also supports bags nested inside that storage, validating every owner and ancestor. Moving the bag, required pickups and walking remain dependencies. Nested world bags stay protected in Host because native B42.21 item transactions cannot address them. Cold cookable food can use proven constant-temperature ordinary storage; hot food, appliances, custom-temperature containers and state-changing callbacks remain protected. |
| Mod operation chains | Reviewed WashFix, Neat Equipment, TidyUpMeister and Project Cook chains retain their waits and borrowed-item returns. Completed effects are not undone. Shared equipment cleanup, ambiguous/floor returns and Project Cook ingredient cleanup remain protected. |
| Generators and fire | Independent targets can move; shared power areas, indoor buildings, fuel, tools and future kindling retain order. Cancelling repair stops future repetitions; active lighting finishes before cancellation. Better Generator Info requires Toolkit first and reviewed original handlers. |
| SaucedCarts | Independent carried-cart transfers can move within capacity bounds; shared cargo and moving containing carts stay protected. SP uses native cart returns. In-flight MP transfers/returns, world/vehicle transfers and custom callbacks stay protected. A cart held in either hand also protects generator fuel/pickup. |

Only reviewed source versions and unchanged handlers receive these permissions. Unknown effects and changed callbacks keep conservative controls. Native multiplayer effects remain authoritative; item IDs, consumed inputs and completed results are never recreated.

Vehicle siphoning and refuelling choose their container and calculate fuel amounts when their turn begins. Repeated radial-menu clicks therefore use the next suitable container after the previous one fills or empties. Repeated **Fill One/Add One** requests prefer the selected container and then another eligible container of the same type; **Fill All/Add All** keep their selected container IDs and skip those no longer eligible. Missing containers or hoses, removed vehicles and empty/full tanks skip that request without dropping later work. Fuel operations retain native transfers, equipment and fluid transactions; their future inputs keep reordering and individual cancellation protected.

Burnt and smashed vehicle dismantling also queues without interrupting current work. Each wreck checks its target, mask and available blowtorch when its turn begins, after the previous action has consumed its inputs. A removed wreck or missing tools skips that request; native multiplayer wreck removal preserves the remaining queue even when it arrives before the completion message. Native equipment, duration, fuel use, scrap and XP remain unchanged. Wreck operations keep reordering and individual cancellation protected while their future tool dependencies are unresolved.

The window hides and releases its displayed rows when the queue empties, the player dies or the option is disabled. Ordinary game cancellation still clears the queue. There is no dedicated hotkey or close button. Asynchronous mod callbacks that enqueue outside a native operation scope can appear as separate rows; arbitrary mod dependencies cannot be inferred.

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

The standalone Toolkit requires B42.19 or newer within Build 42; the complete selected set requires B42.21. Split-screen highlighting has not been validated.

## Medicine indicators

**Medicine indicators** and **Herbal medicine indicators** are two grouped switches for six medicine indicators and two herb indicators, using the optional MoodleFramework independently of Medicine Moodles. Multiplayer readings come from the server and expire after ten seconds without a fresh response. Sleeping-pill strength updates after extra doses; dried herbs use the same native fields. Both switches apply immediately. This section is hidden without MoodleFramework or with the old MedicineMoodlesB42 active, preventing duplicates. Lemongrass reads the native cooldown directly and displays it as a percentage of the maximum; it requires matching Toolkit Java Patches in single-player or on the multiplayer server. Without a supported reading, only that indicator is hidden. No separate countdown or food-action hooks are installed. Full antidepressant onset has not been validated end to end.

## Compatibility

### Navigator

**Fit Navigator to vehicle dashboard**, shown only with Navigator installed, preserves Navigator's original textured, bevelled monitor housing in a compact shape and tints/positions it for the vanilla dashboard and each Realistic Dashboard driver style. One continuous textured mount sits behind the curved panel edge without covering its controls. Map size follows the dashboard setting within readable bounds; labels and power button retain their native sizes. Routing, animation and dragging stay with Navigator. Disabling the option restores its original UI immediately. Keep `RealisticDash` before `Navigator`. Other dashboard mods and split-screen layouts have not been validated.

### SaucedCarts

With **SaucedCarts**, dedicated servers initialize the upstream drop, unequip and forced-drop hooks. Worn carts spill their cargo on ordinary drops, and stale hand references cannot create a second ground cart. MP clients recognize their own cart after server-completed pickup/equip, avoiding a false cancellation. With Tidy Up Meister, cancellation clears hand references to carts already dropped for a tool, preserving the cart and cargo on the ground. Use Push Cart again to resume pushing.

**Cart world spawns:** shopping carts use retail and warehouse buildings; standalone sheds and farm storage retain wooden/metal SaucedWheelbarrow spawns. Outdoor carts require a nearby building eligible for that type (a three-chunk margin, roughly 24 tiles, includes adjacent parking). Ordinary distant driveways no longer receive these carts. Existing carts and saved spawn decisions remain intact; restart the game/server and explore undecided areas for the new distribution. Spawn rate, building limits and world-spawning switches retain their native effects.

**Cart motion:** selected shopping carts and wheelbarrows use load-dependent acceleration and steering. Shopping carts pivot near the front wheels; wheelbarrows lean into a turn. Native character collision still limits movement. Releasing the cart, aiming, sneaking, injury or a timed action restores ordinary handling.

The wooden wheelbarrow has the refined animation: hands remain attached to its handles, the grounded wheel rolls with actual movement and turns lean up to 7 degrees. Walk, Run and Sprint retain moving legs; cargo affects acceleration and Sprint entry/exit. Releasing Run/Sprint uses a heavy-item braking step and a smooth return to the standing grip. New input interrupts braking. From a settled stop, side input uses full native lateral strides around the front wheel before pushing in the new direction. Cargo slows the stride cadence rather than shortening the steps. Run/Sprint wait for that turn to finish. Releasing the direction returns to standing; an opposite-direction command still requests a slower backward step. Use successive side directions for a U-turn.

This tuning was checked locally with empty/full wooden wheelbarrows on both body models. Remote players currently do not receive the complete cart pose; local capture does not establish multiplayer equivalence. Stationary hip/clothing clearance, the remaining maneuver matrix and natural pickup/put-down transitions remain [open work](../TODO.md#natural-wooden-wheelbarrow-animation). There is no separate cart rigid-body simulation.

### Multiplayer auto-drink

Enable the toolkit on the server and each client. Each player controls auto-drink through the normal game options or bottle context menu. The server ignores the host's saved global auto-drink switch and keeps using each player's own networked preference, including after `reloadoptions`. The mod never saves server changes into the host's `options.ini`.

Water consumption remains native: this does not enable drinking from backpacks, mixtures or unsafe fluids.

### Better Containers

Carried bags and ordinary bags on the ground are supported. To access a bag inside a crate, first take the whole bag into your inventory, open it, then put it back. Removing Better Containers' restriction does not fix the network address of such nested containers; the protection remains enabled.


### Inventory presentation

Toolkit supplies container/bag capacity bars, loose-magazine fill segments and expanded item details. Load **NeatUI Framework**, then **CleanUI**, then **PZ Survivor Toolkit**. Disable the separate **Container Capacity Indicator** and **Item Details** mods; their functionality is now built in. Existing display and sorting preferences are preserved.

Capacity bars use the player's effective capacity and follow the actual inventory icons, including nested bags, expanded stacks and scaled icons. They remain available on container buttons and in icon views when switching between CleanUI's enhanced and vanilla inventories. **Options > Mods > Toolkit: Container Capacity** controls magazine segments.

In details view, a research badge marks items with recipes the current character can research, respecting native knowledge and skills. Seeds and full seed packets show known planting seasons: a green star for the best month, a green circle in season, yellow for a risky month and red outside the season. Learn the crop's season information first; empty packets are excluded. Turning off `PlantGrowingSeasons` hides planting information.

Seed tooltips also show water requirements, growth time at the current farming-speed setting, planting/best/risky months and the crop image. **Options > Mods > Toolkit: Planting information** independently controls badges and tooltips, optional unsuitable months and a star for crops without a defined best month. Previous Seed Season Indicator preferences are preserved. Disable the separate **HasResearch** and **SeedSeasonIndicator** mods. Item categories and tag filtering keep their existing meanings.

### Quartermaster

Toolkit includes Quartermaster's storage designations, automatic distribution,
storage Manifest and ingredient fetching for vanilla and Neat Crafting. Disable
the separate Quartermaster mod when updating; existing assignments, presets and
options retain their identifiers.

**Warehouse** works in single-player and menu Host. Open it from the sidebar tools
menu or right-click the craftable **Storage Manifest** notebook. Search by item
name, choose a Toolkit tag and sort the item/tag/count columns. Select an item to
see the containers holding it, including their configured names, icons, colors,
coordinates, counts and the age of each sample.

This is a shared ledger of designated storage for the cooperative world; it is
not a private safehouse inventory. The authority samples loaded storage in small
batches and open windows poll about every two seconds. Contents can lag behind an
ongoing transfer or crafting action. Unloaded areas retain explicitly marked
last-known contents; the ledger does not load those areas. A connection error
keeps the last received list visible. Closing the window stops its polling.
Legacy single-player snapshots remain available until the corresponding loaded
storage is sampled again. The window is read-only: it does not fetch items.
The original implementation and assets are credited in the
[third-party notices](../PZSurvivorToolkit/THIRD_PARTY_NOTICES.md).

To distribute carried loot, configure destination containers with **Configure container...**,
open the source bag in your inventory, then right-click an item inside it and choose
**Distribute Loot**. The command sorts eligible items from that bag; you can keep it
on your back. Favorite items, items protected by enabled organizedCategories Stick,
and items without a matching destination stay put. Pinning an item or item type
controls its display order; it does not protect it from transfer.
The inventory toolbar also has **Distribute Loot** for its selected container.
For a vehicle trunk, open it in the loot window and use that window's button.

Right-click a world container or its button in the loot window to open the same editor. With Better Containers enabled, it also contains **Name**, **Choose icon**, **Colour** and **Reset look**. The first tag selected in this editor fills only empty name, icon and colour fields. Selecting an exact item uses its own icon and its primary tag's colour, without filling the name. Later selections leave these values alone; every field can still be edited manually. Opening an existing configuration does not change its appearance. Save applies appearance and sorting together; Cancel discards the draft. **Reset look** clears appearance without clearing sorting and lets the next selection suggest a fresh look. Sorting presets do not supply an appearance. Bags and other targets that cannot be sorting destinations retain their existing rename/customize controls.

### Item tags

For the organizedCategories taxonomy, disable **Better Containers > Show Advanced Display Categories** so organizedCategories supplies the category IDs. Unknown category IDs remain readable as individual tags.

Toolkit imports organizedCategories categories as independent, localized tags: for example `foodPerishable_fruit` becomes Food, Perishable and Fruit; Electrical is shared by electrical tools and crafting supplies. Tags use vanilla pictograms and stable family colors: Food green, Electrical yellow, Tools blue, Medical red and Materials brown. Qualifiers such as Perishable, Fruit and Preserved have clock, apple and jar icons; qualifiers inherit the item's family color. Text remains visible and missing icons fall back to text/color. Quartermaster and the tag dropdown use the same associations. Native inventory and both CleanUI inventory modes display compact chips in the category column, with a `+N` overflow indicator and a tooltip listing every tag. The column dropdown offers tag filters alongside exact categories. **Options > Mods > PZ Survivor Toolkit > Show item tags** restores the original presentation and controls when disabled.

Choose **Combine tags...** in the inventory column dropdown to select multiple tags. Each tag cycles between neutral, included and excluded; the rule matches all or any included tags, with exclusions taking precedence. Search and the family dropdown narrow the tag list; the match preview shows actual inventory items before Apply. Clear resets the draft; Cancel keeps the previous filter. Exact-category and single-tag filters remain available.

All 209 defined tags have native game icons, including shared ammunition icons for calibers; labels stay visible to distinguish them. Unknown/custom categories use a generic clipboard icon and keep their exact names. The schema contains 357 exact category mappings: all 274 organizedCategories translation IDs plus the known assignments found in the installed B42.21 game and selected mod sources. Both `FurnitureDoor` and `furnitureDoor` retain their original IDs. Saved exact-category filters keep matching after a category receives semantic tags. Arbitrary runtime category overrides remain opaque rather than being guessed from their names. Use `tools/check_tag_categories.py` with explicit game/mod roots to audit another installation.

The **Saved tag filters** submenu saves the current tag rule under a name, reapplies it or deletes it. Saving under an existing name replaces that rule. These filters are local to your client and available across saves; text search is kept separate. Two alternating files under `Zomboid/Lua/PZSurvivorToolkit_TagFilters_*.txt` retain the previous snapshot if a write is interrupted. These inventory filters are independent of storage designations.

Quartermaster's category picker defaults to tags. Selecting Food or Electrical selects matching whole categories; a dash indicates a partial selection. If a tag covers only part of a category, it opens the rule editor and saves stable tag IDs, so EN/RU clients use the same assignment. Switching to exact categories retains refinement, individual items and presets. Batch category selection saves exact category IDs; the separate Tag rule also supports combined dynamic matching.

The separate **Tag rule** button opens the same grouped editor with a preview of matching item types. Saved container and preset rules are evaluated when sorting, alongside manually selected categories, individual items and preset links. For example, Food + Perishable with Meat excluded accepts perishable non-meat items; an explicit manual Meat selection still accepts meat. Newly available categories covered by the tag schema match without reselecting them; unknown categories remain opaque until mapped. Other mods continue receiving their exact category IDs. Disabling tags suspends dynamic matching and retains the rules for re-enabling.

Single-player Quartermaster presets are global to the game profile cache and use the paired snapshots `Lua/PZSTQuartermasterPresets_a.txt` and `Lua/PZSTQuartermasterPresets_b.txt`. Back up both. Existing `QuartermasterPresets.txt` and `PZSTQuartermasterTagRules.txt` are imported and retained as the migration baseline; later changes use snapshots and require the current Toolkit reader. An interrupted write can recover the previous complete pair. Multiplayer presets retain their server ModData storage.

Planting inputs have Farming and Seed tags in addition to their existing roles: sunflower seeds remain Food, and medicinal herbs remain Medical. Empty seed packets have Farming without Seed. Tags follow native crop definitions and packet recipes; the game still decides whether a particular item is fresh, whole or otherwise valid for planting. Inventory filters and Quartermaster rules test each item, so choosing Seed does not include other snacks, vegetables or empty packets sharing its category.

Container-editor writes use the acting player's server-validated location, exact container, safehouse and lock checks. Sorting selections, tag rules and changed appearance are accepted together. Stale revisions are refused; reopen the configuration window after a conflict. Copy/paste sorting retains its existing full-object ModData transport.

### Item Details

Expanded rows show remaining uses; condition, head condition and sharpness; ammunition including a chambered round and weapon attachments; food, cooking/freezing and Nutritionist values; fluid contents and quantities; clothing condition and holes. Ordinary native details remain the fallback for other items. Vehicle parts also work with **organizedCategories**.

Configure labels, bars, numeric values, Nutritionist details and stack sorting under **Options > Mods > Toolkit Item Details**. The old Item Details preference keys remain valid. Sorting uses the configured direction for each item family and sorts only the configured prefix of an expanded stack; all remaining items, physical selections and Shift-selection anchors stay intact. The native visible-child limit is unchanged. With Better Containers, food details leave space for its freshness percentage.

### TV & Radio ReInvented

The TV/radio settings section and its adapters are registered only when TV & Radio ReInvented is active. Installed but disabled mods do not expose settings or receive patches. With TV & Radio ReInvented enabled, inventory and outside clicks keep its windows open. Close the window with the restored X button at its top right. **Options > Mods > PZ Survivor Toolkit > Keep TV/radio windows open** is enabled by default; disabling it immediately restores the original outside-click closure and hidden close button. These settings are local to each client. Native device/range cleanup remains unchanged.

On native macOS, Toolkit Java Patches resolves TV & Radio ReInvented video requests against the actual active mod directory before native caching and loading. The original mod owns its catalog and initialization; Toolkit keeps no separate list of videos. Matching Java Patches is required for this path correction. A separate `Project Zomboid.app/workshop` symlink is no longer required. Keep the complete TV mod installation, including its `.bik` files; a Lua-only copy cannot supply videos. Other platforms keep the upstream video loader; Windows/Linux playback has not been validated. Toolkit now handles device recognition on EN/RU clients itself; keep the old `TVRadioReinventedFix4220` disabled.

**Improve VHS controls** adds direct click-to-eject, tapes from native reachable loot containers and personal bags, and drag-and-drop onto the TV slot. The slot turns green for a VHS and red for an invalid drop. The selection list marks only fully watched tapes with the same checkmark as the inventory. Unfinished tapes have no marker and appear first; history belongs to the current character. Insertion uses native pickup and device actions, with ownership checked on client and server. Disable the option to restore the original TV slot/menu controls.

### Vehicle mechanics

Right-click a removable part in the vehicle mechanics window and select **Uninstall to ground**. The part is left at your character's feet when removal succeeds, including light bulbs and heavy parts; there is no weight threshold. Tools, skills, work duration and the chance of damaging a part remain native. The original **Uninstall** action keeps its usual inventory destination and its fallback to the ground when the inventory has no room. Disable **Uninstall vehicle parts to ground** in Mod Options to hide the extra command; already queued actions keep their chosen destination.

In multiplayer, install Toolkit on the server and every client. No additional mod or Java patch is required for this action. Modded vehicles have not been validated.

### Toolkit Java Patches

The separate [Java patch guide](../JavaPatches/README.md) owns the supported engine fixes, bytecode guards, loader setup and activation checks. The complete selected set requires it on the server and every client.

## Known limitations

The native scenario runner currently supports macOS and invokes game callbacks programmatically. This does not establish physical mouse/controller operation, Windows/Linux, WAN latency, long-session behavior or every combination of third-party mods. See [native scenarios](../tests/native_queue/README.md) for runnable checks and acceptance criteria.

Java Patches 0.1.15 guards native body updates and rejects new server treatment requests arriving after their patient disconnects. The earlier clothing-visual synchronization mismatch remains unexplained; successful clinical actions do not establish a clean runtime. The [medical investigation in TODO](../TODO.md#near-term-adapters) records remaining checks.
