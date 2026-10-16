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
- The adjacent **tools icon** opens Wishlist (when enabled), context menu rules and Toolkit settings. Settings open scrolled to the Toolkit section. Window buttons retain their text with a shared muted warm style.
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
- **Grab/Put amount** accepts one positive whole-number budget for the entire selected batch. It captures exact items and destination, rechecks reachability and character identity on confirmation, and uses native transfer actions. Favourites, equipped items and heavy forced-drop objects are skipped. Rejected pickups stop their own batch without cancelling another client's same-numbered transaction. The independent switch is hidden with TakeAnyAmount active.

## Context menus

**Group context menu actions** groups known actions automatically across native inventory, world, vehicle and health context menus. Categories cover food, equipment, health, crafting, maintenance, devices, transfers, world interaction, vehicles, farming and research. Common actions are ordered before secondary and destructive commands using fixed purpose-based priorities: use/equip/heal/read for carried items, pickup for loot, opening/traversal in the world and entry/control/refuelling for vehicles. This is a curated default, not measured usage or adaptive click tracking. Equal-priority actions keep their native relative order; unknown commands and manual placements remain anchored. Native section titles and portion/recipe selectors retain their structure. Exact repeated commands are shown once, including inside native submenus; actions on different targets or with different arguments, tooltips or metadata remain separate. Each selected-item batch operation appears once, keeping the other native single-item choices. Short menus stay compact; unknown mod commands remain visible. Existing callbacks, icons, tooltips and portion/recipe submenus are preserved. **Context menu rules** in the same Mod Options section lets you search actions encountered while playing, place an action in a group or the main menu, hide it, or restore automatic defaults. Rules are saved locally per client. Disable the feature to restore the original menus immediately. This section is hidden while either Context Menu Organizer or Context Menu Organizer World is active. No additional Workshop mod or change to the selected INI is needed.

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
| Medical treatment | Independent wounds and supplies can move; the same wound, future supply types, clothing effects and shared tools retain order. Supported active treatments stop through native cleanup. Missing supplies or unavailable patients stop only their operation. Use the context menu for splints: the native drop handler rejects valid states. |
| Carried bags | Independent transfers can move when every destination and ancestor has capacity. Moving/equipping/consuming a containing bag remains a dependency. SP can account for space freed by a prior pickup; MP keeps conservative bounds. Synthetic proximity endpoints and unknown capacity callbacks stay protected. |
| Mod operation chains | Reviewed WashFix, Neat Equipment, TidyUpMeister and Project Cook chains retain their waits and borrowed-item returns. Completed effects are not undone. Shared equipment cleanup, ambiguous/floor returns and Project Cook ingredient cleanup remain protected. |
| Generators and fire | Independent targets can move; shared power areas, indoor buildings, fuel, tools and future kindling retain order. Cancelling repair stops future repetitions; active lighting finishes before cancellation. Better Generator Info requires Toolkit first and reviewed original handlers. |
| SaucedCarts | Independent carried-cart transfers can move within capacity bounds; shared cargo and moving containing carts stay protected. SP uses native cart returns. In-flight MP transfers/returns, world/vehicle transfers and custom callbacks stay protected. A cart held in either hand also protects generator fuel/pickup. |

Only reviewed source versions and unchanged handlers receive these permissions. Unknown effects and changed callbacks keep conservative controls. Native multiplayer effects remain authoritative; item IDs, consumed inputs and completed results are never recreated.

Vehicle siphoning and refuelling choose their container and calculate fuel amounts when their turn begins. Repeated radial-menu clicks therefore use the next suitable container after the previous one fills or empties. Repeated **Fill One/Add One** requests prefer the selected container and then another eligible container of the same type; **Fill All/Add All** keep their selected container IDs and skip those no longer eligible. Missing containers or hoses, removed vehicles and empty/full tanks skip that request without dropping later work. Fuel operations retain native transfers, equipment and fluid transactions; their future inputs keep reordering and individual cancellation protected.

Burnt and smashed vehicle dismantling also queues without interrupting current work. Each wreck checks its target, mask and available blowtorch when its turn begins, after the previous action has consumed its inputs. A removed wreck or missing tools skips that request; native multiplayer wreck removal preserves the remaining queue even when it arrives before the completion message. Native equipment, duration, fuel use, scrap and XP remain unchanged. Wreck operations keep reordering and individual cancellation protected while their future tool dependencies are unresolved.

The window hides and releases its displayed rows when the queue empties, the player dies or the option is disabled. Ordinary game cancellation still clears the queue. There is no dedicated hotkey or close button. Asynchronous mod callbacks that enqueue outside a native operation scope can appear as separate rows; arbitrary mod dependencies cannot be inferred.

## Survivor Wishlist

The separate `PZSurvivorWishlist` folder contains an independent wishlist mod, required and already enabled in the selected INI after the crafting/UI mods. The preparation command includes it for the server and every client. It needs neither Shopping List nor WANTED.

- Press **K** or choose **Open wishlist** from the sidebar Toolkit tools icon. With Wishlist alone, its tools icon opens the list directly. Search the catalog by item name or full type; a sample or recipe is not required. Set the desired quantity and add the item.
- Native inventory context menus and the native, Neat Crafting, Neat Building and Project Cook crafting windows can add wanted items. Crafting offers results and missing ingredients; choose one alternative when a recipe accepts different items. Fluids and partial uses are not treated as exact piece counts: these entries ask for one suitable container/item and say to check its contents or remaining uses.
- **Sharing** grants editing to named server usernames (including offline players), your current faction, or both. Everyone with access edits the same list; only its owner changes access. The list selector chooses where additions go. All unfinished goals in your accessible lists are highlighted. Concurrent changes against an old revision are rejected with a prompt to review the refreshed list.
- Quantities are shared goals. **Carried by you** counts only your own inventory and carried bags. Mark completed goals manually, so one player's inventory does not silently complete a group objective.
- Highlights apply to visible inventory rows and loose wanted objects currently in your character's field of view, on the same floor and within 15 tiles. Containers, corpses and contents of bags on the ground are never scanned or outlined. CleanUI's two inventory modes and Better Containers' combined item view are supported. With Toolkit installed, wishlist colours take priority on wanted ground items.
- **Options > Mods > Survivor Wishlist** separately controls inventory highlights, ground highlights and crafting controls, plus colour and hotkey. Use the native window close button or Escape to close its windows.

Native single-player Wishlist UI, storage and lifecycle have not been validated end to end.

Back up the server directory `Zomboid/Lua/PZSurvivorWishlist/` with the world and preserve its encoded save path on restore. See [backup and server setup](../MOD_INSTALL.md#server). Ground highlighting and the shortcut target the primary local player; secondary split-screen players are unsupported by those controls.

## Visibility and rendering

Only loose world items on the player's current floor and within the configured radius are eligible. There is no item-type whitelist; mod-added items use the same checks.

Highlighting requires the tile to be in the character's **current field of view**, as reported by `IsoGridSquare:isCanSee`. Previously seen tiles alone are insufficient. This is stricter than everything drawn on screen: the game can still draw static items that do not receive a highlight.

The effect uses the game's native rendering. Sprite and atlas items receive an outline; some live 3D models receive a colour tint instead. The mod does not replace the renderer to force identical outlines.

The standalone Toolkit requires B42.19 or newer within Build 42; the complete selected set requires B42.21. Split-screen highlighting has not been validated.

## Medicine indicators

**Medicine indicators** and **Herbal medicine indicators** are two grouped switches for six medicine indicators and two herb indicators, using the optional MoodleFramework independently of Medicine Moodles. Multiplayer readings come from the server and expire after ten seconds without a fresh response. Sleeping-pill strength updates after extra doses; dried herbs use the same native fields. Both switches apply immediately. This section is hidden without MoodleFramework or with the old MedicineMoodlesB42 active, preventing duplicates. Lemongrass is an estimated maximum cooldown because its randomized native timer is private; the estimate starts after server-confirmed healing and is not saved across reloads. Full antidepressant onset has not been validated end to end.

## Compatibility

### Navigator

**Fit Navigator to vehicle dashboard**, shown only with Navigator installed, preserves Navigator's original textured, bevelled monitor housing in a compact shape and tints/positions it for the vanilla dashboard and each Realistic Dashboard driver style. One continuous textured mount sits behind the curved panel edge without covering its controls. Map size follows the dashboard setting within readable bounds; labels and power button retain their native sizes. Routing, animation and dragging stay with Navigator. Disabling the option restores its original UI immediately. Keep `RealisticDash` before `Navigator`. Other dashboard mods and split-screen layouts have not been validated.

### SaucedCarts

With **SaucedCarts**, dedicated servers initialize the upstream drop, unequip and forced-drop hooks. Worn carts spill their cargo on ordinary drops, and stale hand references cannot create a second ground cart. MP clients recognize their own cart after server-completed pickup/equip, avoiding a false cancellation. With Tidy Up Meister, cancellation clears hand references to carts already dropped for a tool, preserving the cart and cargo on the ground. Use Push Cart again to resume pushing.

**Cart world spawns:** shopping carts use retail and warehouse buildings; standalone sheds and farm storage retain wooden/metal SaucedWheelbarrow spawns. Outdoor carts require a nearby building eligible for that type (a three-chunk margin, roughly 24 tiles, includes adjacent parking). Ordinary distant driveways no longer receive these carts. Existing carts and saved spawn decisions remain intact; restart the game/server and explore undecided areas for the new distribution. Spawn rate, building limits and world-spawning switches retain their native effects.

**Cart motion:** body and hand animation tracks use matching clip speeds and transitions. Normal walking turns ease into a light load-dependent response: empty carts stay close to ordinary steering, full carts turn more slowly. Running and sprinting retain native steering. Releasing a cart, aiming, sneaking, injury or a timed action restores ordinary handling; while running, restoration of the walking setting waits until that setting is readable again. External turn-controller changes take precedence until the cart is released. This adds steering inertia, without separate wheel physics or new collision behavior.

### Multiplayer auto-drink

Enable the toolkit on the server and each client. Each player controls auto-drink through the normal game options or bottle context menu. The server ignores the host's saved global auto-drink switch and keeps using each player's own networked preference, including after `reloadoptions`. The mod never saves server changes into the host's `options.ini`.

Water consumption remains native: this does not enable drinking from backpacks, mixtures or unsafe fluids.

### Better Containers

Carried bags and ordinary bags on the ground are supported. To access a bag inside a crate, first take the whole bag into your inventory, open it, then put it back. Removing Better Containers' restriction does not fix the network address of such nested containers; the protection remains enabled.


### CleanUI / Container Capacity Indicator

When using both mods, load them in this order: **NeatUI Framework, CleanUI, PZ Survivor Toolkit, Container Capacity Indicator**. Toolkit aligns CCI bars with CleanUI's visible inventory icons, including equipment headers, hidden equipment, expanded stacks and scaled icons. CCI keeps its own capacity calculations, colours and magazine setting. Toolkit preserves its item and container-button bars when CleanUI switches between enhanced and vanilla inventories, including icon views; it also supplies the alpha omitted by B42's native icon renderer. Without that pair, the adapter does nothing. If CCI loads before Toolkit, the adapter logs the required order and leaves its renderer unchanged.

With **Better Containers**, Toolkit owns category filters, preserving its proximity and container features. Keep Toolkit before Better Containers and MP Fast Forward; malformed speed commands are rejected before they reach MP Fast Forward. The selected INI already sets this order.

### Item tags

Toolkit imports organizedCategories categories as independent, localized tags: for example `foodPerishable_fruit` becomes Food, Perishable and Fruit; Electrical is shared by electrical tools and crafting supplies. Tags use vanilla pictograms and stable family colors: Food green, Electrical yellow, Tools blue, Medical red and Materials brown. Qualifiers such as Perishable, Fruit and Preserved have clock, apple and jar icons; qualifiers inherit the item's family color. Text remains visible and missing icons fall back to text/color. Quartermaster and the tag dropdown use the same associations. Native inventory and both CleanUI inventory modes display compact chips in the category column, with a `+N` overflow indicator and a tooltip listing every tag. The column dropdown offers tag filters alongside exact categories. **Options > Mods > PZ Survivor Toolkit > Show item tags** restores the original presentation and controls when disabled.

Quartermaster's category picker defaults to tags. Selecting Food or Electrical selects all currently available matching categories; a dash indicates a partially selected tag. The view switch retains exact category refinement, individual items and presets. Saves and multiplayer requests still contain Quartermaster's exact legacy category IDs; selecting a tag is a batch selection, not a saved rule that automatically accepts categories introduced by a future mod update. Native tag scenarios cover single-player; multiplayer and the complete selected mod set remain unverified.

### Item Details

With **Item Details** enabled, Toolkit restores condition display and sorting for vehicle parts categorized by **organizedCategories**. Expanded stacks retain every item when they exceed Item Details' sorting limit: the configured prefix is sorted and the remaining items stay in the list. Sorting and display preferences remain in **Options > Mods > Item Details**.

Load **CleanUI**, then **PZSurvivorToolkit**, then **BravoItemDetails**; keep **organizedCategories_core** last. The selected INI already includes this order. The compatibility fix lives in Toolkit; keep the official Workshop files unchanged on the server and clients. Native Item Details scenarios cover single-player; multiplayer and the complete selected mod set remain unverified.

### TV & Radio ReInvented

The TV/radio settings section and its adapters are registered only when TV & Radio ReInvented is active. Installed but disabled mods do not expose settings or receive patches. With TV & Radio ReInvented enabled, inventory and outside clicks keep its windows open. Close the window with the restored X button at its top right. **Options > Mods > PZ Survivor Toolkit > Keep TV/radio windows open** is enabled by default; disabling it immediately restores the original outside-click closure and hidden close button. These settings are local to each client. Native device/range cleanup remains unchanged.

On native macOS, Toolkit loads the 16 videos shipped with TV & Radio ReInvented v1.3 from the actual active mod directory. A separate `Project Zomboid.app/workshop` symlink is no longer required. Keep the complete TV mod installation, including its `.bik` files; a Lua-only copy cannot supply videos. Other platforms keep the upstream video loader; Windows/Linux playback has not been validated. Toolkit now handles device recognition on EN/RU clients itself; keep the old `TVRadioReinventedFix4220` disabled.

**Improve VHS controls** adds direct click-to-eject, tapes from native reachable loot containers and personal bags, and drag-and-drop onto the TV slot. The slot turns green for a VHS and red for an invalid drop. The selection list marks only fully watched tapes with the same checkmark as the inventory. Unfinished tapes have no marker and appear first; history belongs to the current character. Insertion uses native pickup and device actions, with ownership checked on client and server. Disable the option to restore the original TV slot/menu controls.

### Vehicle mechanics

Right-click a removable part in the vehicle mechanics window and select **Uninstall to ground**. The part is left at your character's feet when removal succeeds, including light bulbs and heavy parts; there is no weight threshold. Tools, skills, work duration and the chance of damaging a part remain native. The original **Uninstall** action keeps its usual inventory destination and its fallback to the ground when the inventory has no room. Disable **Uninstall vehicle parts to ground** in Mod Options to hide the extra command; already queued actions keep their chosen destination.

In multiplayer, install Toolkit on the server and every client. No additional mod or Java patch is required for this action. Modded vehicles have not been validated.

### Toolkit Java Patches

The separate [Java patch guide](../JavaPatches/README.md) owns the supported engine fixes, bytecode guards, loader setup and activation checks. The complete selected set requires it on the server and every client.

## Known limitations

The native scenario runner currently supports macOS and invokes game callbacks programmatically. This does not establish physical mouse/controller operation, Windows/Linux, WAN latency, long-session behavior or every combination of third-party mods. See [native scenarios](../tests/native_queue/README.md) for runnable checks and acceptance criteria.

Native multiplayer medicine has unresolved late body-update and clothing-visual synchronization errors. Their cause is not established; successful clinical actions do not mean a clean runtime. The [medical investigation in TODO](../TODO.md#адаптеры-ближайшего-этапа) records the reproducer and remaining control comparisons.
