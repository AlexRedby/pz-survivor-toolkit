# Inventory, bulk actions and storage

[Features](../FEATURES.md) · [Installation](../../MOD_INSTALL.md)

Use this guide for selection, transfers, item details, tags, sorting and the Warehouse.

- [Bulk actions](#bulk-actions)
- [Better Containers](#better-containers)
- [Inventory presentation](#inventory-presentation)
- [Quartermaster](#quartermaster)
- [Retained items](#retained-items)
- [Item tags](#item-tags)
- [Item Details](#item-details)

## Bulk actions

- **Cut selected clothing** adds **One item / Cut selected clothing (N)** inside the native cut/rip submenu when at least two eligible garments are selected. Handles mixed cotton, denim and leather using each item's native recipe; denim/leather require a suitable cutting tool. Only selected instances are consumed; favourites, worn/held items and ineligible clothing are skipped. Supports grouped stacks and reachable containers. Disable it independently in Mod Options.
- **Dismantle selected electronics** extends the native dismantling action with **One item** and **Dismantle selected (N)** when at least two eligible items are selected, including grouped stacks and mixed electronics. Both variants retain the native recipe icon. Flashlights keep their battery action alongside dismantling, with the two dismantling variants in a third-level submenu. Supports the native simple electronics, electronic devices, miscellaneous electronics, power bars and battery-lighter dismantling recipes. Favourites and worn/held items are skipped. Each action binds its selected item explicitly and keeps native tools, duration, outputs and XP; tools from reachable containers are transferred once and returned after the batch. Normal cancellation stops the remaining queue. If another player takes a selected item, the rejected pickup safely stops this batch. Toolkit prevents an already-rejected bulk pickup from cancelling another client's same-numbered transfer; ordinary game actions and manual cancellation keep the native network protocol. Disable this feature in Mod Options to hide the command.
- **Eat selected (N)** appears in the Eat submenu while the action queue is enabled, with full, half and quarter choices where the native menu offers them. It handles selected ready-to-eat food, including herbs and flowers, and the verified native `OpenCannedFood` / `OpenCannedFood2` recipes. Each can opens through native crafting; eating waits for its exact created food ID before returning tools and restoring the mask. Partial portions work in SP and MP. Repeated clicks reserve different selected items; favorites and already queued food are excluded. Missing food or being too full skips affected steps without clearing unrelated work. Group cancellation finishes an ongoing eating/preparation step, stops an unfinished opening recipe and retains already-created food; late results cannot restart eating. A missing server result times out after 30 seconds without recreating or consuming food. Eat Smart, changed callbacks and unverified opening recipes keep their existing commands.
- **Remove batteries from selected items** adds **One item / Remove batteries from selected (N)** to the native Remove Battery recipe. Each selected compatible device keeps its identity, the extracted battery uses the game's native charge conversion, and devices picked up from bags or nearby containers use the native return-to-container action after the batch. This covers the native crafting recipe, not radio power-panel actions.
- **Unload selected magazines and firearms** extends native unloading with **One item / Unload selected (N)**. Supports loose magazines and firearms with integral magazines, including mixed selections. Chambered rounds and magazines inserted into weapons keep their separate native actions.
- **Remove attachments from selected weapons** adds **Remove all parts from selected weapons (N)** beside the existing per-part choices. Uses the native detachable-part checks and tool requirements, preserving each part's identity.
- The dismantling, clothing, battery and weapon bulk features have their own Mod Options switches. They skip favourites and worn/held items at selection, bind exact selected IDs, and stop the remaining queue on cancellation or stale targets. Native weapon callbacks and queue hooks retain Tidy Up Meister's existing transfer and equipment policies when that mod is active; they do not force an additional return to the previous hand item.
- **Grab/Put amount** accepts one positive whole-number budget for the entire selected batch. It captures exact items and destination, rechecks reachability and character identity on confirmation, and uses native transfer actions. Favourites, equipped items and heavy forced-drop objects are skipped. A mixed selection also skips Toolkit-protected items; deliberately selecting one row/stack permits its transfer. The original selection determines that exception even when the requested quantity is one. Rejected pickups stop their own batch without cancelling another client's same-numbered transaction. The independent switch is hidden with TakeAnyAmount active.

## Better Containers

Carried bags and ordinary bags on the ground are supported. To access a bag inside a crate, first take the whole bag into your inventory, open it, then put it back. Removing Better Containers' restriction does not fix the network address of such nested containers; the protection remains enabled.

## Inventory presentation

Toolkit supplies container/bag capacity bars, loose-magazine fill segments and expanded item details. Load **NeatUI Framework**, then **CleanUI**, then **PZ Survivor Toolkit**. Disable the separate **Container Capacity Indicator** and **Item Details** mods; their functionality is now built in. Existing display and sorting preferences are preserved.

Capacity bars use the player's effective capacity and follow the actual inventory icons, including nested bags, expanded stacks and scaled icons. They remain available on container buttons and in icon views when switching between CleanUI's enhanced and vanilla inventories. **Options > Mods > Toolkit: Container Capacity** controls magazine segments.

In details view, a research badge marks items with recipes the current character can research, respecting native knowledge and skills. Seeds and full seed packets show known planting seasons: a green star for the best month, a green circle in season, yellow for a risky month and red outside the season. Learn the crop's season information first; empty packets are excluded. Turning off `PlantGrowingSeasons` hides planting information.

Seed tooltips also show water requirements, growth time at the current farming-speed setting, planting/best/risky months and the crop image. **Options > Mods > Toolkit: Planting information** independently controls badges and tooltips, optional unsuitable months and a star for crops without a defined best month. Previous Seed Season Indicator preferences are preserved. Disable the separate **HasResearch** and **SeedSeasonIndicator** mods. Item categories and tag filtering keep their existing meanings.

## Quartermaster

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
[third-party notices](../../PZSurvivorToolkit/THIRD_PARTY_NOTICES.md).

To distribute carried loot, configure destination containers with **Configure container...**,
open the source bag in your inventory, then right-click an item inside it and choose
**Distribute Loot**. The command sorts eligible items from that bag; you can keep it
on your back. Favorite items, items protected with Toolkit's **Protect from mass transfer** action,
and items without a matching destination stay put. Pinning an item or item type
controls its display order; it does not protect it from transfer.
The inventory toolbar also has **Distribute Loot** for its selected container.
For a vehicle trunk, open it in the loot window and use that window's button.

Right-click a world container or its button in the loot window to open the same editor. With Better Containers enabled, it also contains **Name**, **Choose icon**, **Colour** and **Reset look**. The first tag selected in this editor fills only empty name, icon and colour fields. Selecting an exact item uses its own icon and its primary tag's colour, without filling the name. Later selections leave these values alone; every field can still be edited manually. Opening an existing configuration does not change its appearance. Save applies appearance and sorting together; Cancel discards the draft. **Reset look** clears appearance without clearing sorting and lets the next selection suggest a fresh look. Sorting presets do not supply an appearance. Bags and other targets that cannot be sorting destinations retain their existing rename/customize controls.

## Retained items

Select items in any inventory, bag or vehicle trunk, then right-click and choose
**Protect from mass transfer** (RU: **Закрепить предмет**). Toolkit leaves those
specific instances behind during Distribute Loot, Take/Transfer All and mixed
bulk transfers. A deliberate transfer of one row or stack still works and keeps
the protection; choose **Remove transfer protection** to clear it. Protection
follows the item rather than reserving a quantity of its type in a particular
vehicle. Existing organizedCategories Stick marks remain effective.

In Host, the server validates the exact item, acting player, containing inventory,
proximity and access before saving and synchronizing a change. There are no
organizedCategories player/sandbox switches to enable. Disable that separate mod.

## Item tags

Toolkit supplies item classification; disable the separate organizedCategories mod and **Better Containers > Show Advanced Display Categories**. Native ScriptItem loot categories remain unchanged. Unknown category IDs remain readable as individual tags.

Toolkit owns classification and presents the established organizedCategories taxonomy as independent, localized tags: for example `foodPerishable_fruit` becomes Food, Perishable and Fruit; Electrical is shared by electrical tools and crafting supplies. Tags use vanilla pictograms and stable family colors: Food green, Electrical yellow, Tools blue, Medical red and Materials brown. Qualifiers such as Perishable, Fruit and Preserved have clock, apple and jar icons; qualifiers inherit the item's family color. Text remains visible and missing icons fall back to text/color. Quartermaster and the tag dropdown use the same associations. Native inventory and both CleanUI inventory modes display compact chips in the category column, with a `+N` overflow indicator and a tooltip listing every tag. The column dropdown offers tag filters alongside exact categories. **Options > Mods > PZ Survivor Toolkit > Show item tags** restores the original presentation and controls when disabled.

Choose **Combine tags...** in the inventory column dropdown to select multiple tags. Each tag cycles between neutral, included and excluded; the rule matches all or any included tags, with exclusions taking precedence. Search and the family dropdown narrow the tag list; the match preview shows actual inventory items before Apply. Clear resets the draft; Cancel keeps the previous filter. Exact-category and single-tag filters remain available.

Known tags use native game icons, with labels distinguishing shared icons such as ammunition calibers. Unknown/custom categories keep their names and a generic icon. Saved exact-category filters remain valid when semantic tags are added. Custom runtime overrides are not guessed from their names.

The **Saved tag filters** submenu saves the current tag rule under a name, reapplies it or deletes it. Saving under an existing name replaces that rule. These filters are local to your client and available across saves; text search is kept separate. Two alternating files under `Zomboid/Lua/PZSurvivorToolkit_TagFilters_*.txt` retain the previous snapshot if a write is interrupted. These inventory filters are independent of storage designations.

Quartermaster's category picker defaults to tags. Selecting Food or Electrical selects matching whole categories; a dash indicates a partial selection. If a tag covers only part of a category, it opens the rule editor and saves stable tag IDs, so EN/RU clients use the same assignment. Switching to exact categories retains refinement, individual items and presets. Batch category selection saves exact category IDs; the separate Tag rule also supports combined dynamic matching.

The separate **Tag rule** button opens the same grouped editor with a preview of matching item types. Saved container and preset rules are evaluated when sorting, alongside manually selected categories, individual items and preset links. For example, Food + Perishable with Meat excluded accepts perishable non-meat items; an explicit manual Meat selection still accepts meat. Newly available categories covered by the tag schema match without reselecting them; unknown categories remain opaque until mapped. Other mods continue receiving their exact category IDs. Disabling tags suspends dynamic matching and retains the rules for re-enabling.

Single-player Quartermaster presets are global to the game profile cache and use the paired snapshots `Lua/PZSTQuartermasterPresets_a.txt` and `Lua/PZSTQuartermasterPresets_b.txt`. Back up both. Existing `QuartermasterPresets.txt` and `PZSTQuartermasterTagRules.txt` are imported and retained as the migration baseline; later changes use snapshots and require the current Toolkit reader. An interrupted write can recover the previous complete pair. Multiplayer presets retain their server ModData storage.

Planting inputs have Farming and Seed tags in addition to their existing roles: sunflower seeds remain Food, and medicinal herbs remain Medical. Empty seed packets have Farming without Seed. Tags follow native crop definitions and packet recipes; the game still decides whether a particular item is fresh, whole or otherwise valid for planting. Inventory filters and Quartermaster rules test each item, so choosing Seed does not include other snacks, vegetables or empty packets sharing its category.

Container-editor writes use the acting player's server-validated location, exact container, safehouse and lock checks. Sorting selections, tag rules and changed appearance are accepted together. Stale revisions are refused; reopen the configuration window after a conflict. Copy/paste sorting retains its existing full-object ModData transport.

## Item Details

Expanded rows show remaining uses; condition, head condition and sharpness; ammunition including a chambered round and weapon attachments; food, cooking/freezing and Nutritionist values; fluid contents and quantities; clothing condition and holes. Ordinary native details remain the fallback for other items. Vehicle parts retain their detailed Toolkit classifications.

Configure labels, bars, numeric values, Nutritionist details and stack sorting under **Options > Mods > Toolkit Item Details**. The old Item Details preference keys remain valid. Sorting uses the configured direction for each item family and sorts only the configured prefix of an expanded stack; all remaining items, physical selections and Shift-selection anchors stay intact. The native visible-child limit is unchanged. With Better Containers, food details leave space for its freshness percentage.
