# Changelog

Player-visible changes and fixes, grouped by component. For current behavior and limits, see [features](docs/FEATURES.md) and the [Java guide](JavaPatches/README.md).

- [Selected mod set](#selected-mod-set)
- [PZ Survivor Toolkit](#pz-survivor-toolkit)
- [Survivor Wishlist](#survivor-wishlist)
- [Toolkit Java Patches](#toolkit-java-patches)

Version labels come from component metadata. Parallel branches sometimes reused a label; consolidation entries describe the combined behavior. These headings are version references, not publication dates. Third-party mod selection and compatibility notes are in the [catalog](docs/MODPACK.md).

## Selected mod set

- **Fixed:** Prepared that DAMN Library copies remove the two obsolete Plastic Welding Gun battery recipes. The existing standard recipes preserve the gun and transfer its battery charge; the duplicate removal recipe that created a full battery without draining the gun is no longer available. Preparation requires a complete `--damnlib` source, verifies the reviewed script and leaves Workshop inputs untouched.

- **Fixed:** Prepared CleanUI copies refresh every member of visible collapsed food stacks at the existing one-second interval. Older food beyond the first 50 items can now become stale and regroup while a younger header remains fresh. Preparation requires an explicit complete CleanUI source, checks the reviewed source hashes and includes the corrected copy for every client/Host without changing Workshop downloads.

- **Added:** Immersive Snow, JB's Bugs In Lights, the main '92 Jeep YJ Wrangler with required that DAMN Library, and Furniture Push & Pull (67 Mod IDs / 62 Workshop items). The library loads before the Jeep and vehicle repair/salvage remain last. Downloaded B42 metadata confirms the main Jeep requires only `damnlib`; optional JP18 adds Jurassic Park spawns and requires the main Jeep. JP18/Viewpoint modules stay disabled; existing sandbox settings are preserved. Full-pack SP/Host visuals, performance, vehicle behavior and filled-furniture/Quartermaster conservation remain unverified.

- **Added:** Three New Music packs with songs released before 1993: ABBA Gold (`NMBJABBA`, Workshop `3784065691`), Queen (`NMBJQ`, `3777937059`) and Fleetwood Mac (`NMBJFM`, `3751236222`), after `NewMusic` (62 Mod IDs / 57 Workshop items). Published album lists span 1975-1992 and the packs total approximately 633 MB. Existing sandbox settings are preserved; full-pack SP/Host playback remains unverified.

- **Added:** New Music (`NewMusic`, Workshop `3739256725`) to the B42.21 selection (59 Mod IDs / 54 Workshop items), for audible cassette/CD/vinyl playback. The base includes a Zomboid OST recording; additional song packs are selected separately. Full-pack SP/Host playback, performance and TV & Radio ReInvented coexistence remain unverified.

- **Added:** Spongie's Open Jackets (`SpnOpenClothBase` before `SpnOpenCloth`, Workshop `2812326159`) and Climb Ladders (`SubirEscaleras`, Workshop `3774776279`) to the B42.21 selection (58 Mod IDs / 53 Workshop items). Adds open/rolled clothing variants and world-ladder climbing. Optional Fluffy Hair and Build Ladders remain unselected; full-pack SP/Host behavior is unverified.

- **Added:** Vehicle Repair Overhaul and its B42 Vehicle Salvage Overhaul module from Workshop `2757712197`, loaded base-first after the other vehicle mods (55 Mod IDs / 51 Workshop items). Adds repair options and whole-vehicle salvage; full-pack SP/Host behavior and the upstream sandbox-setting controls remain unverified.

- **Added:** Vehicle Aim Roof Fix (`CarRoofFix`, Workshop `3781616141`) after the VVA pair in the B42.21 selection (54 Mod IDs / 51 Workshop items), to keep visible occupants seated during right-mouse look-around/aiming. Full-pack SP/Host behavior remains unverified.

- **Added:** Nick's Turn Off Fridges to the B42.21 selection (53 Mod IDs / 50 Workshop items), with appliance unplug/replug controls and optional per-appliance automation. Full-pack SP/Host behavior remains unverified; plug appliances back in before removing the mod.

- **Added:** Detailed Skill Tooltips, Foraging Tooltip Extended and Custom Light Switch to the B42.21 selection (52 Mod IDs / 49 Workshop items). Adds skill-level explanations, foraging-radius information and buildable room-light switches. Author version/MP claims are documented in the catalog; full-pack SP/Host behavior remains unverified.

- **Added:** Archery Nexus with Wilderness Progression: Archery Nexus to the B42.21 selection (49 Mod IDs / 46 Workshop items), with the base loaded before its companion. Includes crafting/progression, arrow recovery and draw endurance/strain; full-pack and Host behavior remain unverified. Existing sandbox settings are unchanged.
- **Added:** Vanilla Vehicles Animated and its ZombieBuddy-based Animated Vehicle Parts Fix to the B42.21 selection (47 Mod IDs / 44 Workshop items). Optional VVA submods and the outdated multiplayer synchronization addon remain disabled. SP visuals, lighting coexistence and Host animation synchronization are not yet verified.

## PZ Survivor Toolkit

### 0.1.314

- Allow moving supported unstarted Host makeup while its kit remains in a carried or nested bag. Track exact ancestor membership and shared container dependencies without extracting or reserving supplies; keep world sources, depletion, equipment writers and uncertain callbacks protected.

### 0.1.313

- Reduce native item reads when drawing a collapsed food stack's freshness indicator. Read every member's current freshness, then calculate the stale marker only for the least-fresh member; preserve ties, live changes and native food ageing.
- Skip freshness scans for stack headers that draw neither a bar nor a percentage, including unhovered percentage-only headers and bars below the minimum width. Preserve child percentages and existing pane ownership.

### 0.1.312

- Allow moving owned, unstarted Host makeup around independent queued work and before resumable reading. Track the exact root kit, current plain cosmetics and declared output type; keep prior resource changes, shared writers, capacity-sensitive transfers, depletion and unsupported producers protected.

### 0.1.311

- Extend Disassembly to native copper, gold, silver and aluminum salvage, plus clothing, sheets and belts that can be recovered into materials. Follow native item-state and equipment restrictions without adding XP or furnace roles.
- Add Empty for liquid vessels with no current contents. Update filters and container rules after filling or emptying, preserve coherent previews and manual corrections, and carry the state through warehouse snapshots without inferring it for older records.

### 0.1.310

- Synchronize paid makeup results when the kit remains in an accessible worn or nested bag, nearby container or ground bag. Reuse exact shared item access with bounded ancestor membership checks, preserving native creation, consumption and unsupported callbacks.

### 0.1.309

- Keep supported makeup previews on an isolated avatar instead of changing real clothing before Apply. Preserve SP instant application and native Host execution, prevent stale preview restoration, and allow cancellation only for owned unstarted Host actions.
- Send the exact paid makeup output before clothing synchronization in Host, fixing the native notification of the kit instead of its result without changing creation or consumption.

### 0.1.308

- Include jewelry accepted by the native gold, silver and gemstone scrapping recipes in Disassembly filters and container rules. Preserve recipe state checks and manual tag corrections; decorative pieces and kept tools remain excluded, and jewelry scrapping does not imply Smelting or skill experience.

### 0.1.307

- Allow moving unstarted hair/beard dye and supported gel/spray hairstyles around independent queued work. Preserve exact dye identity, native late styling selectors and costs, including GreasedBack double use; keep shared materials, unsupported replacements and active bodies protected.

### 0.1.306

- Add Broken from the current native item state, independent of partial wear, empty supplies and food spoilage. Show healthy/broken preview alternatives for native wear classes and tools degraded by crafting inputs without creating items or running callbacks.
- Allow broken tools into explicitly matching Broken or Smelting container rules, including combined rules and linked presets. Preserve ordinary usable-tool selections, exclusions, manual tag corrections and named-item precedence.
- Keep Broken separate from Sharpen in previews and store the current broken state in warehouse snapshots, retaining older snapshot formats and independent smelting eligibility.

### 0.1.305

- Add Sharpen for usable items with missing sharpness, including partly dulled blades. Read native attributes without modifying sharpness; fully sharpened and broken items are excluded, while favorite items remain eligible.
- Classify nonempty propane lantern refill bottles as Fuel instead of Lighting. Empty refill bottles lose Fuel, while actual refillable lanterns keep their lighting role.
- Include native sewing thread, including sinew and modded thread, in crafting/tailoring materials while preserving animal-origin and other roles.
- Carry sharpening state through filters, container rules and warehouse snapshots, preserving older formats and manual corrections. Script previews keep sharpness independent of stains and remaining supplies.

### 0.1.304

- Skip Smart Deposit's nearby storage scan when the selection contains no movable items. Preserve mixed-selection routing, favorite and retained-item rules, and fresh checks when dropping items.

### 0.1.303

- Allow moving unstarted plain haircuts, hair tie/untie and beard trims across independent queued work. Keep exact tool, appearance and equipment dependencies ordered, preserve native timing and P4 returns, and retain protection for gel/spray styling, dye, modified callbacks and started operations.

### 0.1.302

- Avoid rescanning a dropped radio's tile on every render of its open controls window. Reuse the matched item while its live list position and identity remain valid, and resolve again after pickup, replacement, list changes or rebinding. Late multiplayer arrivals remain discoverable; translated labels and native window controls are preserved.

### 0.1.301

- Separate dumbbells and barbells, including forged equipment, from Hygiene into Fitness. Equipment declared by additional fitness exercises gains the same role; toiletries retain Hygiene.
- Extend Dirty to currently stained, natively washable clothing and bags. Clean/dirty previews remain independent of remaining supplies, and washing removes the state without changing bandaging roles.
- Add Smelting for material subjects of verified native furnace recipes, including metal scrap, ore, broken glass and sand. Exclude accompanying fuel, tools and flux; partial sandbags need remaining material.
- Preserve current laundry and smelting states in filters, container rules and warehouse snapshots, including older snapshot formats and manual tag corrections.

### 0.1.300

- Derive fishing and trapping bait roles from native definitions and current food eligibility. Preserve food uses and distinguish cooked bait, trap-incompatible additions and usable supplies in filters and warehouse snapshots.
- Include genuine adhesive-repair supplies such as glue, adhesive tape and recipe-specific cloth in Repair, while keeping unrelated uses. Add Ignition for usable matches, lighters and firestarters; empty garden sprayers no longer count as plant treatments.
- Classify fully depleted ordinary batteries as Junk instead of crafting/electrical supplies. Fractional remaining charge and rechargeable vehicle batteries keep their roles; manual corrections still take precedence.
- Keep dynamic choices visible before those item states occur, use coherent preview combinations, and read older four-role warehouse snapshots alongside the expanded capability format.

### 0.1.299

- Keep fluid category previews from consuming game random numbers. Read configured starting amounts without sampling them; explicit empty containers stay empty and ranged defaults have stable preview categories. Existing items continue to use their current contents.

### 0.1.298

- Add Bandaging, Disinfection and Dirty tags from native medical properties. Dirty bandages and ripped sheets remain usable for bandaging; fluid disinfection follows the current alcohol concentration and remaining amount.
- Extend Fuel to propane and native fire fuels, including charcoal. Current contents and remaining uses distinguish usable fuel from empty containers, with coherent filter previews and captured warehouse states.
- Clarify Musical, For Liquids and Russian Feed labels while preserving saved tag identifiers and manual corrections.

### 0.1.297

- Rename the visible Experience tag to Learning while preserving saved rules and assignments; books and recordings retain their common training role without skill subdivisions.
- Derive Beverage and Alcohol from current fluid components, including diluted alcoholic drinks and empty containers. Water mixed with medical alcohol does not become an alcoholic drink; Beverage describes contents, not safe drinking. Warehouse snapshots preserve the observed role instead of assuming factory contents.
- Unify Condiment and Seasoning as one native cooking-additive role. Salt, sauces and oils remain Cooking Ingredients; ordinary beans no longer inherit the additive role. Migrate old tag selections and manual corrections, preserving restrictive legacy exclusions.

### 0.1.296

- Add Raw, Cooked and Burnt tags from each food item's current native state, independently of spoilage. Ordinary uncookable fruit is not labelled Raw; burnt food can still be Rotten.
- Support cooking-state choices and coherent rule previews in inventory and container filters, retaining manual tag corrections. Warehouse snapshots preserve captured cooking states and keep older, uncaptured states unknown until refreshed.

### 0.1.295

- **Added:** Container groups share a name, icon, color, sorting filters, tag rules and priority. Create a group from the container editor or select an existing one to inherit its settings. Save changes for the whole group or only the current container; a local edit detaches that container. Groups work with duplicate exclusion disabled and synchronize through the existing revisioned Host authority.
- **Added:** Optional **No duplicates** sorting reserves one copy of each item type across the whole batch, per container or across all discovered members of its group. Skill-book volumes remain distinct, and extra copies continue to other matching destinations in the existing priority order. The setting is included in copy/paste. Ordinary manual transfers are unchanged; concurrent Host transfers by different players still require coordination.

### 0.1.294

- Replace the visible broad Food tag with concrete, overlapping roles: Can Eat, Cooking Ingredient, existing meat/vegetable/fruit/beverage/alcohol tags, and Feed for pet food. Saved Food rules and manual assignments retain their previous membership without reappearing as new tag choices.
- Derive Cooking Ingredient from native meal additions, food bases and consumed cooking-recipe inputs. Include meat, vegetables, bread, flour, seasonings, peanuts and native milk powder; exclude utensils, fuel, mere can-opening steps and fishing chum. Unknown callback-only recipes stay unclassified.
- Classify liquid ingredients from their current contents, preserving empty and unsuitable-fluid negatives. Capture ingredient state in warehouse rows so filtering and grouping do not substitute a bottle's default contents; older snapshots keep unknown fluid state conservative.

### 0.1.293

- Allow canceling an already-started native haircut, beard trim or hair/beard dye without discarding subsequent queued work. Preserve borrowed-tool and equipment cleanup, cosmetic state and unspent styling/dye resources; Host requires the exact still-started server receipt.

### 0.1.292

- Derive Experience and Recipe tags independently from each recording. Combined lessons retain both tags, recipe-only recordings are supported, and container previews use real combinations without inventing content. Keep manual tag corrections and saved exact categories.
- Add Disassembly for the consumed subjects of supported native dismantling recipes and scrap furniture, with skill tags from their XP rewards. Exclude kept tools and unrelated craft inputs; inspect live item restrictions without executing recipes. Unknown recipe callbacks remain unclassified.
- Add Can Eat separately from Food using native Eat/Open and Eat behavior. Exclude Smoke/Drink and inedible ingredients; preserve Container and Liquid on fluid vessels regardless of their current contents.
- Project warehouse entries through an explicit snapshot API, preserving recorded content and manual assignments without passing snapshot tables to native InventoryItem predicates.

### 0.1.291

- Fixed: a native successful petting animation no longer clears unrelated queued work. The original animal effect and stop cleanup are retained; continuation waits for the exact native action to leave and for Host stop acknowledgement. Manual cancellation, invalid targets and unsupported handlers retain native behavior.
- Fixed: natural-stop preservation verifies the original base stop handler before suppressing its queue reset, including the existing Fitness path. Preinstalled foreign stop effects and replaced native action ownership remain protected.

### 0.1.290

- Fix Configure container filter fonts and control sizing. Select refined tags with one checkbox click, reflect active rules in checked rows and clear them with category selections; preserve explicit advanced conditions.
- Keep the advanced tag editor in front of its owner and stop scrolled rows painting beyond its lists. Clarify the electronic-furniture tag label.
- Remove the redundant General tag from ordinary containers while retaining saved filter behavior. Classify toy cap guns and their caps as toys in inventory tags and Quartermaster rules without changing native item properties.
- Use the native furniture cabinet icon for the Furniture tag.
- Rename the Surface tag to Table with the native whole-table icon. Keep Table alongside Storage and Container on the chestnut drawers, which also support native surface crafting; preserve exact legacy-category selections.
- Derive Wearable tags from native body slots and wearable metadata across clothing, medical items and bags. Combine Furniture and Container for storage furniture using native sprite properties; hand-carried containers stay outside Wearable. Java Patches provides exact script-preview equipment metadata without creating items.
- Use Readable for native reading and content-view actions, including photographs, newspapers, maps, learning materials and written notes. Reserve Literature for recreational books, magazines and comics; exclude blank writing materials, disabled reading and hollow-book containers. Reading filters remain item rules as content changes.
- Add live Fresh, Stale and Rotten food tags for inventory filters and container sorting. Use native expiry boundaries for all spoiled food, expose future state choices without assigning an age to script types, honor manual tag corrections in previews, and preserve per-item routing within mixed stacks. Replace empty-jar nonperishable/preserved icons with labelled food cans.
- Allow rotten worms to become compost while preserving native fresh-worm breeding, compost yield and other items' compost restrictions.
- **Development:** Add an isolated item catalogue with category crates and an exportable item index for manual classification review.

### 0.1.289

- **Performance:** Better Containers freshness indicators read only visible inventory rows and skip hidden panels and dragged rows. Visible stacks still use their least-fresh member with current values; bar/percentage options and the original inventory-mode scope are preserved. Partial rows are clipped to the inventory contents.

- **Performance:** Reuse unchanged action-queue rows and groups with matching Toolkit Java Patches, including expanded batches. Direct queue edits remain visible immediately; current action, progress, titles and controls stay live. Unsupported action tables and installations without the helper retain exact Lua scanning. Hidden panels no longer rebuild cleared snapshots and rows.

### 0.1.288

- Improved: queue move/cancel explanations distinguish required finishing steps, unreviewed action handlers and work that is still adding its next steps. Tooltips and rejected cancellation clicks identify the blocking action; existing item/state/capacity evidence and edit permissions are preserved.

### 0.1.287

- Fixed: waiting beard trimming and hair/beard dye actions can be cancelled without losing borrowed-item cleanup or independent queued work. Native shaving colours and dye fluid costs remain unchanged; active edits retain their resource protections.
- Fixed: unreviewed replacements of the base action constructor cannot inherit native grooming cancellation permissions.
- Fixed: ordinary equipment removal uses the shared verified native branch when SaucedCarts is loaded, so headwear preparation no longer blocks cancelling queued dye actions. Cart handling and required cleanup remain protected.

### 0.1.286

- Fixed: waiting native haircuts can be cancelled after tool preparation. Borrowed scissors retain their required return and independent queued work continues; native appearance changes and styling-item costs remain unchanged.

### 0.1.285

- **Fixed:** Cancelled-queue previews validate recovery without constructing actions or repeatedly searching inventories for every saved item. Restore still resolves and validates current state before creating fresh actions.
- **Fixed:** Empty and collapsed Wishlist windows avoid unused inventory counts and row rebuilds, refresh on expansion and reopening, and keep row actions bound to their displayed accessible list.

### 0.1.284

- **Fixed:** Better Containers proximity behavior survives CleanUI interface switches, preserving aggregate selections, shared hover highlights and container-page policies for both interface classes.
- **Fixed:** Ground highlighting keeps discovery progress while walking, so dense piles and items farther inside the radius do not remain undiscovered until the player stops. Normal and Wishlist highlighting retain the existing per-tick work limits.
- Development: native lifecycle observers can capture settled receipt/effect snapshots before queue advancement retires required cleanup; failed diagnostics cannot block paid native completion.
- Fixed: closing a deferred mod session after queue editing is disabled no longer drops a proven borrowed-item return from an already accepted cancellation. Closed sessions still reject new work; already-running transfers retain their exact observation handle, and the earned return can finish before the independent queue tail.

### 0.1.283

- **Fixed:** Collapsed loot windows defer unused item rows and container tooltips while keeping header counts and nearby contents current. Hover, pin and drag expansion restore fresh rows before input or drawing; active selections and marquee gestures retain immediate updates.

### 0.1.282

- **Fixed:** Wishlist storage uses bounded directory names, so long save paths no longer prevent lists from loading. Each journal verifies the full save identity; existing lists migrate with readback verification and their original files are retained.

### 0.1.281

- Fixed: disabling the queue editor after an accepted operation cancellation no longer discards the borrowed-item return or independent queued actions. The exact native step, server outcome and required cleanup finish once, including grounded fitness equipment; reset, replaced actions and unrelated asynchronous commands retain their existing cancellation protections.

### 0.1.280

- Fixed: disabling the action queue during an admitted native completion no longer drops its independent pending tail. The matching phases finish once; fresh disabled actions retain native handling, while resets and replaced native episodes revoke stale callbacks. Existing asynchronous media cancellation rules remain unchanged.

### 0.1.279

- Fixed: shared callback and instance-field ownership checks now use Kahlua's actual own-field semantics in queued approach and fluid-completion guards, medical validation and temporary callback restoration. Inherited fields cannot masquerade as required owned state; native costs and effects are unchanged.
- Development: action-queue checks can run as one offline group, collect all failures and explicit coverage gaps, and qualify the same behavior vectors against native Kahlua without launching the game.

### 0.1.278

- **Fixed:** The hidden loot window now skips unused row, count and tooltip work during nearby-container discovery in B42.21. Kahlua's inherited `rawget` lookup had prevented the existing optimization from attaching. Live contents, explicit refreshes, selected items and reopening retain their existing behavior.
- **Fixed:** Inventory tag drawing and generator completion restore inherited callbacks without pinning them to an instance. Queue editing/recovery now distinguishes genuinely owned action methods from inherited replacements when validating supported actions.

### 0.1.277

- Fixed: reviewed WashFix All commands keep their body, clothing and bandage steps together when the action queue is disabled. Transformation completion retains its existing edit protection and native resource costs.
- Fixed: a failed reviewed WashFix completion restores its temporary water rule before propagating the original error, without repeating item or resource effects.

### 0.1.276

- Fixed: WashFix All commands for body washing and ordinary clothing no longer discard the body step when clothing preparation requests another approach to the source. This also works with the action queue disabled, where the command still replaces prior work.
- Reviewed WashFix All commands combining body washing and ordinary clothing now use the common clothing completion boundary. Native body washing, soap and water costs, item returns and paid effects retain their behavior; transforming-item aggregates keep their existing safeguards.

### 0.1.275

- Fixed: the translucent inventory drag preview stays at its original offset from the cursor while earlier queued transfers remove rows. Applies to native and CleanUI inventory lists, including Shift-selected ranges and expanded stacks.

### 0.1.274

- Fixed: washing off makeup in Host now synchronizes its removal from the player inventory. Native washing costs, partial cleaning and interruption behavior are preserved with the action queue enabled or disabled.

### 0.1.273

- Reviewed WashFix clothing pickup, inventory-retry, washing and return chains now use the common action-completion boundary. Native resource costs, cancellation/reset ownership and ordinary item returns retain their behavior; body washing, mixed commands and transforming bandage recipes keep their existing handling.
- Clothing-only WashFix chains now retain queue integration after the reviewed late SaucedCarts transfer hook. Unknown transfer replacements and other washing branches retain their existing safeguards.

### 0.1.272

- Fixed: Project Cook permits the first ingredient when starting a new dish from a food base with inherited ingredients, including filled bread slices. Its first-addition step still allows only one new selection; native eligibility, portions, recipe limits, hunger and nutrition stay unchanged.

### 0.1.271

- Preserve cart steering and grip while limping. Use the native injury gait and speed, respect native Run/Sprint eligibility, and keep directional turns/reverse and moving healing synchronized between Host players.

### 0.1.270

- Fixed: Project Cook resolves the selected pot to its exact live inventory instance after pickup and refreshes ingredient availability when it enters the inventory, in SP and Host. A stale floor reference no longer hides usable ingredients or makes ingredient addition retry with “Not Available” after the ingredient has reached the inventory. Recipe checks, native costs, leftovers and the remembered return destination remain unchanged, with the action queue enabled or disabled.

### 0.1.269

- Fixed: In multiplayer, Tidy Up Meister no longer queues native clothing restoration for an original item that has left the character's inventory, such as an exercise bag left behind or taken by another player. Valid exact-ID replacements and unrelated restoration actions retain their normal behavior.

### 0.1.268

- Keep the retained-item mark when refilling a welding torch, including saved Stick marks. Context-menu refill returns the replacement torch to its original container after the authoritative result arrives. Replace the obsolete consumed-torch return so it cannot cancel the following propane-tank return in Host; native fuel costs remain unchanged.

### 0.1.267

- Fixed: Fitness measures earned active native frames instead of the synchronized world clock. Host clock corrections no longer shorten or extend a workout; preparation, repeated reads and the confirmation frame add no time. Native interruptions, effects and stop/cleanup ordering stay intact.

### 0.1.266

- Return accelerated time to normal when a nearby audible alarm starts. Uses MP Fast Forward's existing safety veto in multiplayer and native speed controls in single-player; adds no notifications or windows. Requires the matching Java Patches alarm bridge.

### 0.1.265

- **Fixed:** Native Fitness keeps its full selected duration after preparation, including with queue editing disabled. Natural completion retains the independent tail, waits for the original native stop/server receipt, and restores the exact borrowed gear before the next action. Explicit cancellation, movement, exhaustion and changed ownership still interrupt through the native path.

### 0.1.264

- **Fixed:** Native get-up continuations retain their place before later queued work, including Fitness and context-menu door/window callbacks with queue editing disabled. The original callback and native action admission still run; reset, cancellation or changed ownership revoke late continuation additions.

### 0.1.263

- **Shopping carts:** Replace the stiff procedural gait with body-leading turns built from native walking, retaining knee motion, heel/toe roll and a gently moving torso. Use phase-matched straight and turning clips with slight leg separation; stationary pivots and wheelbarrows retain their existing clips.

### 0.1.262

- **Vehicles:** Enter with a leading-foot step, bend and transfer weight over the planted foot, then bring the trailing leg inside. Use a separate exit motion with a foot planted outside before standing. Match the native driving seat and retain native action timing, cancellation and completion events. Requires Java Patches 0.1.55 for doorway position and foot contacts.

### 0.1.261

- **Fixed:** A completed Host action no longer discards the remaining queue while its matching server receipt is still in transit. The same cancellation and ownership checks apply with queue editing enabled or disabled; native effects are never replayed. Requires Java Patches 0.1.54.

### 0.1.260

- Declare the replaced standalone Survivor Wishlist, Quartermaster, Container Capacity Indicator, Item Details, HasResearch, Seed Season Indicator, organizedCategories, Medicine Moodles, Take Any Amount and TV & Radio ReInvented 42.20 fix mods incompatible with Toolkit, preventing accidental duplicate activation in the native Mods selector.

### 0.1.259

- **Fixed:** Native Fitness preparation with queue editing disabled now synchronizes its cleared secondary hand in Host and returns a prop borrowed from a placed bag to that exact recovered bag. Restoration requires the observed native pickup and, in Host, its completed item transaction; missing storage or changed bindings cannot select a replacement prop or bag.

### 0.1.258

- **Action queue:** Cancel a confirmed pending borrowed-item return separately to keep that item carried while its current action continues. Preserve later dependencies and capacity, exact item ownership and other required cleanup; later cancellation and P4 idle restoration do not recreate the deliberately removed return.
- **Action queue / Host:** Recognize a detached transfer-group copy of the same exact carried item after native inventory replication, retaining live source, item identity, callback and resource checks.
- **Action queue UI:** Show neutral crosses before a permission check, distinguish an unavailable hovered cancel, and retain the reason when a click is rejected. Group and child controls keep fresh validation at release.

### 0.1.257

- **Exercise:** Use continuous game time for queued workout progress and completion, counting Host training from its confirmed server start. Remove the extra whole-minute pause after 100% while retaining the full selected duration and confirmed equipment recovery.

### 0.1.256

- **Action queue:** Share the reconstruction and insertion of interrupted reading/building actions after their existing local-stop or server-cancellation checks. Preserve saved progress, operation ownership and authoritative result guards.
- **Performance:** Avoid unused queue snapshots for generator commands and unsupported medical producers; reuse the ordered child list when capturing replacement-bandage actions.
- **Action queue:** Share deferred expansion across native, Toolkit and reviewed mod commands. Close the native child-insertion scope before propagating a producer error, so later independent requests cannot be inserted into the failed operation. Preserve already-enqueued children, native error handling, successful empty expansion and existing edit/cleanup contracts.

### 0.1.255

- **Action queue / Host:** Let an exactly matched, server-completed native action finish its original client callback when the optional queue is disabled. Preserve explicit cancellation, movement, reset and stale-transaction guards; disabling queue controls no longer makes confirmed preparation clear unrelated queued work.

### 0.1.254

- Add a separate Host server recording switch beside local vehicle diagnostics. Authenticate the real Host connection, show confirmed server status and file paths, and handle delayed or missing replies without claiming success.

### 0.1.253

- Add a vehicle-diagnostics window under Toolkit Mod Options with a live recording checkbox and status. Start and stop bounded client logs during play without JVM flags or a restart; the checkbox is not saved between launches.

### 0.1.252

- **Inventory:** Keep Shift selection anchored to the same physical item when retained-item groups refresh in CleanUI, including repeated refreshes before the next render.

### 0.1.251

- **Action queue / Host:** Preserve the independent queue tail when cancelling an in-flight preparation step whose effect the server has already completed. Finish that exact native step before required equipment recovery; explicit movement, stop and reset still cancel normally.
- **Action queue / cleanup:** Scope the food-mask clothing contract to its own restoration actions so it cannot block bag restoration and borrowed-prop returns after exercising.
- **Action queue / fitness:** Restore hands, worn bags and borrowed exercise props only after their native preparation effects are confirmed, including grounded storage and its exact native pickup. Wait for Host transactions and exact item replication on normal completion and cancellation; share guarded prop returns so repeated cleanup cannot duplicate a return. Preserve native workout duration, costs, stop behavior and queue-disabled controls.

### 0.1.250

- **Performance:** Avoid duplicate nearby-container discovery after a simultaneous turn and tile change. Defer unused details rows and counts while the loot window is fully hidden and idle; rebuild on reopening while preserving reachable containers, Better Containers aggregates and live transfer/crafting inputs. Build CleanUI container-weight tooltips when the window is shown instead of during hidden discovery.
- **Performance:** Build filter-menu item snapshots only when needed and skip the extra empty-selection projection. Reuse capacity-bar weight readings for up to 200 ms, invalidating on container changes; transfer capacity checks remain immediate.

### 0.1.249

- **Inventory:** Allow deliberate transfers of several retained items through drag-and-drop, context menus, quantity commands and Smart Deposit. Keep protection during Take/Transfer All, automatic Move to Floor and loot distribution; manual moves keep their retained flags.

- **Inventory:** Replace the compressed Keep marker with a high-contrast lock drawn at up to 16 pixels. Put expanded-child markers in the empty icon gutter so they do not cover condition or fluid values. Use the same lock in the retention menu, with clearer EN/RU wording and a tooltip explaining mass-transfer protection and deliberate manual moves.

### 0.1.248

- **Changed:** Vehicle glass is replacement-only: remove Vehicle Repair Overhaul repairs for windshields, side/rear windows and military glass in both Lua and script-recipe modes. Keep glass removal/installation, other vehicle repairs and metal window armor/frame repairs.
- **Fixed:** Hide empty Repair submenus for installed and loose vehicle parts when Vehicle Repair Overhaul offers no repairs, including fully broken parts with their repair option disabled. Keep unavailable choices that explain missing materials or skills, and preserve sandbox repair rules.


### 0.1.247

- **Vehicle occupants:** Keep the character seated while entering or exiting a vehicle, preventing the native chair animation from raising their head and shoulders through visible roofs. Preserve the native animation completion events and 0.625-second duration; vehicle positioning, sounds, cancellation and Host action handling stay with the game.

### 0.1.246

- **Performance:** Skip ground discovery and the extra Wishlist search radius when no active goal has a concrete wanted item type. Authoritative list changes and new sessions update this idle gate without scanning membership on every tick.
- **Performance:** Reuse successful ground-item visibility and highlight checks within one tick when discovery overlaps maintenance. Keep next-tick visibility/ownership reads, movement discovery and dense-pile budgets.
- **Performance:** Reduce repeated native reads during vehicle-light updates: reject unlit cars before proximity work, read local-player positions once per update, and share each car's script and the live lamp-list reference. Keep the 100 ms cadence, source membership checks and lamp, power, movement and unload cleanup.

### 0.1.245

- **Exercise:** Put worn and held storage on the ground before exercising instead of carrying its full unequipped weight. Recover the same nearby bags and restore their worn/hand slots afterward, preserving contents and favourite flags. Applies with queue controls enabled or disabled; missing/distant bags and newly occupied worn slots are left alone. Native placement/pickup limits, workout duration, XP and fatigue remain unchanged. Full-pack SP/Host gameplay verification is pending.

### 0.1.244

- **Action queue / cancellation:** Keep preparation, work and required restoration in persistent operation records. Confirm mask removal before retaining its restoration; wait for Host outcomes and exact item replication before releasing independent work. Use confirmed P4 pickup/return episodes when returning borrowed tools, preserving shared ownership, native equipment restoration and explicit equipment choices. Repeated queue cancellation cannot discard already-required restoration, and completed effects are never replayed.

### 0.1.243

- Fix Host item retention and custom tag assignment rejecting accessible vehicle items when replicated vehicle grid squares differ. Match the exact item, vehicle and compartment while retaining live server range, floor, container, nested-bag and SafeHouse admission.
- Preserve the physical Shift-selection anchor when a dirty native/CleanUI redraw refreshes inventory rows with detail-column sorting disabled.

- Preserve the Shift-selection anchor across consecutive inventory refreshes before the next redraw, including Host item-state updates.
- Install category/tag/retention grouping after Better Containers finishes replacing inventory methods, preserving exact stack splits in both CleanUI inventory modes.
- Raise retained (Stick) physical items above ordinary and Better Containers type-pinned items in their inventory section. Separate mixed retained/unretained stacks, keep the selected column order within each group and preserve exact selection through Host updates and release.

- Add a shared world tag catalog with custom tags and editable names, colors and native icons. Catalog and assignment editors keep drafts until Save, support reset/cancel and preserve drafts on concurrent-edit conflicts.
- Add world-wide item-type and exact-instance tag overrides with Automatic / Assign / Remove states. Keep dynamic classification and native categories intact; apply effective tags to inventory chips, filters, context profiles, warehouse views and Quartermaster rules.
- Synchronize catalog and assignments through Host authority, reject stale/inaccessible edits atomically, and preserve deleted tag identities in saved rules so includes cannot match unrelated items.

- **Fixed:** Restore the retained-item marker omitted during the organizedCategories migration. Native/CleanUI inventory details mark mixed stack headers when any instance is protected and only the protected expanded children, including legacy Stick marks; drag previews and icon grids keep their original presentation.
- **Fixed:** Read CRLF legacy category/settings files and preserve an existing vanilla-defaults classification preference, including filled fluids and explicit manual category overrides.

### 0.1.242

- **Action queue / approach:** Queue native approach preparation through one shared mechanism and resolve its route from the actor's position when the operation reaches the front. Preserve native wall/floor/multi-tile route alternatives, selected cursor state and queue-disabled movement; native vegetation, destruction and moveable cursors use the same routing layer without replacing preceding queued work. Preserve the native fishing-net placement fallback and exact destroy-target selection. A positively identified path failure drops its dependent operation while keeping unrelated work.
- **Action queue / editing:** Keep deferred approach preparation transparent to whole-operation editing and reconstruct supported pending approach intent during cancelled-queue recovery. Cancel deferred command rows through the same whole-operation boundary used by validation, so required preparation cannot be detached from its body.

### 0.1.241

- Make the container editor easier to read with a larger icon preview, container identity, an opaque background, compact appearance/sorting sections, labelled searches and explicit tag-rule state. Localize its main controls in English and Russian, explain empty search/selection/preset lists, make the tag-rule dialog opaque with a labelled search, keep the scrollbar aligned through resizing and collapse duplicate icon images while retaining their search aliases.

### 0.1.240

- **Wishlist / vehicle mechanics:** Offer replacement-part wishes only for slots with a native installation operation. Fixed parts such as the vanilla glovebox no longer offer Add to wishlist; replaceable parts remain eligible when tools or skills are missing, including modded installable gloveboxes.

### 0.1.239

- **Added:** Toolkit now classifies items for tags and storage, including fluids and recorded media, while preserving native loot categories. The separate organizedCategories mod is no longer selected.
- **Added:** Protect items from mass transfer through the inventory context menu, including vehicle supplies during Distribute Loot. Single-row transfers still work, and existing Stick marks are preserved.

### 0.1.238

- **Action queue:** Recover the remaining work from the last cancelled queue in one step. Recovery keeps reading progress and skips work that is complete or unsafe to repeat; it checks that items and targets are still available.

### 0.1.237

- **Action queue / televisions:** VHS ejection syncing early in Host no longer drops the remaining queue. The queue waits for the cassette to return and keeps native TV effects intact.
- **Action queue / TV controls:** Reorder independent VHS, playback, volume, channel and mute actions. Power and mute requirements remain in effect; an unavailable TV action is skipped while unrelated work continues.

### 0.1.236

- **Fixed:** Host workouts stop when the selected duration ends, even if the server acknowledges their start late. Equipment restoration and following actions wait until the workout is settled; the queue shows workout progress separately from server confirmation.
- **Fixed:** Preparation and equipment restoration no longer look like extra exercise time in the queue.

### 0.1.235

- **Action queue / P4:** Battery flashlights can return to their hotbar after use even when their charge or light output changed. Flashlights that transform into another item and custom mod behavior remain protected.

### 0.1.234

- **Action queue / P4:** Portable battery radios without media can return to their hotbar after use while keeping their native settings, power and sound behavior.

### 0.1.233

- **Action queue / P4:** Ordinary non-weapon items can return to their hotbar after use, alongside weapons. Devices, items that transform while used, and equipment with uncertain behavior remain protected.

### 0.1.232

- **Action queue:** Returning temporary headwear keeps the game's normal Mohawk hair behavior. If the hair or headwear changes unexpectedly, cleanup is skipped without blocking unrelated queued work.

### 0.1.231

- **Action queue:** Ordinary clothing can be restored safely after replacement, including when another item occupies its slot. The queue preserves required returns and avoids dropping items when inventory capacity is tight. Special clothing, multi-item slots and modified callbacks remain protected.

### 0.1.230

- **Action queue:** Temporary wristwatch use can finish and clean up while its alarm continues or stops naturally. Conflicting equipment slots, watch conversions and modified callbacks remain protected.

### 0.1.229

- **Action queue:** Temporary wristwatch use can be reordered when the watch is worn and held in one or both hands. Its alarm and normal hand/worn restoration are preserved; conflicting slots, ringing watches and watch conversions remain protected.

### 0.1.228

- **Action queue:** Unheld, nonringing wristwatch cleanup can be reordered while preserving its alarm settings. Table clocks, conflicting slots and modified callbacks remain protected.

### 0.1.227

- **Action queue:** Plain headwear can be restored to an empty slot after temporary use when the hairstyle is unchanged. Conflicting slots and modified callbacks remain protected.

### 0.1.226

- **Action queue:** Temporary plain headwear can be removed when the hairstyle is unchanged. Mohawks and uncertain clothing slots keep their existing handling, and cleanup avoids capacity-related item drops.

### 0.1.225

- **Action queue:** Ordinary clothing that is both held and worn can be cleaned up after queued use. Special clothing and changed mod behavior remain protected.

### 0.1.224

- **Action queue:** Items borrowed from a hand can return to their original hotbar slot after queued use. Special equipment and modified hotbar behavior remain protected.

### 0.1.223

- **Craft plans:** Recalculating a crafting plan focuses on the selected recipe and its prerequisites, while keeping material and tool alternatives and checking current supplies before crafting.

### 0.1.222

- **Action queue:** Temporary ordinary clothing can be removed and returned before the queue continues. Held items, activated equipment, special clothing and heavy-item drops remain protected.

### 0.1.221

- **Action queue:** Ordinary clothing restoration waits until the game finishes equipping it before the queue continues. Special equipment and changed mod behavior remain protected.

### 0.1.220

- **Distribution:** Storage matching now handles item tags consistently across rules while preserving explicit-item priority, category filters, broken-tool exclusions and live capacity checks.

### 0.1.219

- **Action queue:** Queued firearm racking no longer blocks unrelated borrowed tools and equipment. The active racking action and items it depends on remain protected.

### 0.1.218

- **Action queue:** Native transfers continue to batch normally when the queue is disabled, including tool returns and supported cart transfers. Cancellation still performs required cleanup, and enabling the queue does not disrupt transfers already underway.

### 0.1.217

- **Cart animation:** Fixed unwanted shifts during cart movement and transitions while preserving the character's normal stride and body pose.

### 0.1.216

- **Settings:** Update only affected consumers after Mod Options commits all controls. Shortcut and unrelated option changes no longer clear ground highlights or refresh inventory, media windows and context menus. Preserve immediate ground-disable cleanup on pause, Wishlist ground settings, tag-dependent menus and live feature switches.

### 0.1.215

- **Action queue:** Borrowed tools now return to the operation that picked them up, even when transfers are combined. Ambiguous or outdated return information is ignored.


### 0.1.214

- **Wishlist:** Multiplayer updates avoid rebuilding unchanged wishlist entries while still applying edits promptly and removing access when membership changes.

### 0.1.213

- **Action queue:** Confirmed tool returns are kept even if a later return fails or times out, so cleanup does not misidentify which items made it back.

### 0.1.212

- **Context menu editor:** Menu examples and previews are prepared only while the editor is open. Newly captured items are selected automatically; saved rules continue to apply in ordinary menus.

### 0.1.211

- **Action queue:** When a group of borrowed items returns only in part, confirmed returns are kept and missing items are not treated as returned. A failed observation cannot stop or repeat the native transfer.

### 0.1.210

- **Action queue:** Cleanup now recognizes a borrowed item only after it reaches its saved destination. Missing, rejected or ambiguous transfers are not counted as successful returns.

### 0.1.209

- **Smart Deposit:** Drag feedback updates promptly when the selection, target or inventory changes, while the actual drop still checks current storage space and item protections.

### 0.1.208

- **Action queue:** Cancelled work returns items to their original destinations without confusing different items that happen to share an ID. Conflicting or outdated return information is skipped while unrelated queued work continues.

### 0.1.207

- **Compatibility:** P4 and ordinary transfers continue to work with the selected Nick's Turn Off Fridges and Better Containers mods.
- **Action queue:** In Host, equipment and pickup actions wait for the server's result before cleanup continues. Late, failed or repeated replies no longer apply to newer actions. Native single-player behavior is unchanged.

### 0.1.206

- **Craft from storage:** Crafting plans now count recipe quantities, partial supplies and tool uses correctly across a batch, while prioritizing carried and nearby items. The game still handles walking, transfers and final recipe checks.

### 0.1.205

- **Action queue:** Delayed equipment returns stay attached to the action that borrowed the item, while required cleanup can finish even if that action is cancelled. Uncertain item ownership remains protected.

### 0.1.204

- **Action queue:** Cancelling an operation still returns borrowed items and restores masks or fitness equipment when appropriate, without disturbing unrelated queued work.

### 0.1.203

- **Automatic distribution:** Each deposit checks current container capacity. A rejected Host transfer no longer prevents items destined for other containers from moving; uncertain results still stop the haul.

### 0.1.202

- **Action queue:** Queue edits now support ordinary food that is fully consumed and replaced by one empty fluid container. Uncertain or custom replacement behavior remains protected.

### 0.1.201

- **Action queue:** Pending ordinary food can be reordered or cancelled when fully eating it creates one plain replacement item. Custom food and uncertain replacement behavior remain protected.

### 0.1.200

- **Warehouse:** Unchanged storage no longer needs a full item-list refresh; changes to contents, containers or appearance still update the list.

- **Warehouse:** Keep the complete footer above the window's resize strip, wrap longer status text and size controls and item/location rows for the active font. Resizing reserves room for both scrolling lists.

### 0.1.199

- **Changed:** Retargeted metal wheelbarrow pickup/setdown to the corrected wrist angle with a closed fist, preserving the grounded approach and accepted body/cart stance.

### 0.1.198

- **Actions window:** Completed queue rows no longer appear clickable during the brief pause before the window refreshes.
- **Drinking water:** Finishing a water drink no longer discards the rest of the queue in single-player or Host. Portions, hydration and action timing remain native; missing or changed bottles remain protected.

### 0.1.197

- **Changed:** Retargeted the metal wheelbarrow pickup and setdown clip to its closer, lower held handles while preserving the grounded approach and shallow crouch.

### 0.1.196

- **Emptying water:** Emptying a bottle no longer interrupts the queue when its volume reaches zero before the native action ends.
- **Action queue:** Pending emptying of ordinary carried clean-water containers can be reordered or cancelled. Drinking from the same bottle, mixed fluids and world or resource containers remain protected.

### 0.1.195

- The Storage Manifest warehouse now works in menu Host as well as single-player. Open it from the sidebar tools menu or the Storage Manifest notebook to search items, view their configured storage locations, and check when each location was last sampled.
- Unloaded areas retain their last-known contents. Existing single-player storage snapshots are kept until that storage is visited again.

### 0.1.194

- Pending cold food in ordinary world storage can be reordered or cancelled in single-player when it cannot keep cooking. Hot food, appliances and custom-temperature storage remain protected; Host handling is unchanged.

### 0.1.193

- Quartermaster storage sorting avoids repeated work when matching named destinations, while preserving destination priority, capacity and category/tag fallback.

### 0.1.192

- In single-player, supported items can be moved to or from bags inside nearby ordinary world storage while queued. Required pickups and walking remain in order; Host does not support this nested-storage case.

### 0.1.191

- Large quantity transfers and bulk food preparation now find reachable containers more efficiently. Confirmation still checks current contents and native transfer rules.

### 0.1.190

- The action queue and medicine indicators do less work when their displayed state has not changed or both indicators are off. Queue grouping, selection and multiplayer readings are preserved.

### 0.1.189

- **Improved:** Pending pickups, food actions and returns can be reordered when using nearby ordinary crates or shelves. Required pickups and walking stay in order; favorite items, cookable food, special containers and uncertain mod behavior remain protected.

### 0.1.188

- Inventory category and tag menus load more quickly on large inventories, while item visibility, selection and native/CleanUI behavior are preserved.

### 0.1.187

- **Changed:** Shopping-cart ground actions approach the push bar and use their own standing acquisition/release clip, preserving native cart and cargo ownership.
- **Fixed:** Metal wheelbarrow setdown no longer briefly splays the feet before blending back into the normal idle stance.
- **Changed:** Metal wheelbarrow pickup and put-down use a separate body clip matched to its grounded handles, with a closer approach between the shafts, planted feet and continuous hand contact.
- **Changed:** Metal wheelbarrows now use the shared wheelbarrow pickup, put-down, cancellation/recovery and movement presentation, including native multiplayer ownership and observer animation.

### 0.1.186

- Context menus and editor previews now handle duplicate options more consistently, while preserving distinct commands and options supplied by mods.

### 0.1.185

- Food and firearm selection menus prepare large selections more efficiently, while rechecking selected items and tools when an action starts.

### 0.1.184

- **Improved:** Ingredient-based food no longer blocks otherwise safe queued transfers between carried containers. The queue still protects uncertain capacity changes and full food replacements.

### 0.1.183

- Queue cleanup for food, fire, generator and mod actions does less repeated work while preserving delayed equipment returns and retries.

### 0.1.182

- **Improved:** Some partial portions of ingredient-based food can be reordered or cancelled while the original dish remains. Empty-container state and unsupported ingredient behavior remain protected.

### 0.1.181

- Long labels fit more consistently in the UI and Storage Manifest, including narrow columns and Unicode text.

### 0.1.180

- **Improved:** Some partial food portions can be reordered or cancelled when the original food remains and the meal leaves an empty container. Custom callbacks, evolved ingredients and full-item replacements remain protected.

### 0.1.179

- **Fixed:** Wishlist highlighting and crafting alternatives update more efficiently on large inventories while preserving mixed-stack matching, filters and vehicle-part requests.

### 0.1.178

- **Fixed:** Wishlist crafting alternatives now account for ingredients already used by a recipe, including exclusive choices and partial items or fluids.

### 0.1.177

- **Fixed:** Large filtered and quantity transfers prepare selections more quickly while still checking current items, protections and destinations when confirmed.

### 0.1.176

- **Fixed:** Filtered transfers and inventory refreshes do less repeated work on large inventories while preserving visible-item selection and native transfer checks.

### 0.1.175

- **Fixed:** Multiplayer queue acknowledgements and floor-placement cleanup no longer retain completed records unnecessarily; late results remain associated with the right player and action.

### 0.1.174

- **Fixed:** Removed three obsolete modern police separator references from the reviewed Vanilla Vehicles Animated profiles after validating and applying their existing bars template. The missing references previously produced startup errors without changing the parsed vehicles. Vehicle parameters and the single existing bars model are preserved; unknown source versions and templates or profiles provided by other mods remain untouched.

### 0.1.173

- **Fixed:** Queue hints and reordering respond more efficiently on long queues while continuing to validate current prerequisites and item dependencies.

### 0.1.172

- **Fixed:** TidyUpMeister floor returns in Host work when they begin immediately after disabling the queue.
- **Fixed:** Updated the reviewed Vanilla Vehicles Animated ranger-car bars reference; unknown versions and profiles remain untouched. Three modern police separator references remain unresolved and visible in the logs.

### 0.1.171

- **Fixed:** A new multiplayer character reapplies the local auto-drink preference after the server connection reply, so respawning with auto-drink disabled no longer leaves the character enabled while the menu shows it disabled.

### 0.1.170

- **Fixed:** In Host, a VHS taken from a backpack can be moved ahead of active shelf reading without losing the insertion or dependent playback.
- **Fixed:** Queue move/cancel capacity checks no longer call the unavailable `next()` global in the game's Kahlua runtime. Shelf returns combined with backpack pickups retain their existing capacity checks without errors while drawing or editing the queue.
- **Fixed:** Corrected reviewed Vanilla Vehicles Animated StepVan trunk decor and police-car bars references. Other mod-provided profiles remain untouched; missing police-separator templates remain unresolved and visible in the logs.

### 0.1.169

- **Fixed:** Long queues and bulk transfers update more efficiently, keeping queue controls and operation labels responsive.

### 0.1.168

- **Changed:** Item Details reads the native Mod Options values directly instead of maintaining a second configuration synchronized on Apply and main-menu entry. Existing preferences, display settings and bounded stack sorting are preserved.
- **Fixed:** Toggling loose-item highlighting no longer refreshes unrelated inventory panes, TV controls or context menus. Applying the full Toolkit options still updates the affected features.

### 0.1.167

- **Fixed:** In Host, ordinary VHS insertion keeps its pending playback when the TV state or tape removal arrives before native completion. The exact started insertion waits for correlated server completion and both effects, including with the Toolkit queue disabled; explicit cancellation and native failure still clear ordinary pending work.

### 0.1.166

- **Changed:** Container configuration now uses the same reliable save path as other Quartermaster commands, preserving access checks and conflict handling.

### 0.1.165

- **Changed:** The sport dashboard headlight button cycles off, low, high and off on successive releases. It keeps the original bulb symbol, six-dot grip and momentary press effect, with the dashboard indicator showing the beam mode. Power steps retain native commands and acknowledgement handling; selecting high does not toggle headlight power.

### 0.1.164

- **Changed:** Quartermaster's storage controls and Mod Options now stay in sync across native and Neat crafting windows, including after a cancelled haul.

### 0.1.163

- **Changed:** Context-menu editor previews now match the live menus, including grouping, scoped rules and saved preferences.

### 0.1.162

- **Fixed:** Wooden wheelbarrow pickup now requires the player to reach the actual handle position before starting the lift. A path shortened by a nearby obstacle leaves the cart on the ground instead of starting from a misaligned stance.

### 0.1.161

- **Fixed:** CleanUI now keeps each inventory drag as one transfer operation, restoring native batching while preserving capacity and multiplayer checks.

### 0.1.160

- **Changed:** The standard dashboard headlight knob uses evenly spaced off/low/high positions: low sits halfway between off and the original on position, with high at the original on position. Matching soft grey faceplate symbols replace the previous layout at every dashboard scale. Clicking retains the native power acknowledgement path and High Beams selection.

### 0.1.159

- **Changed:** Pending portions of ordinary food that leaves an empty container can be reordered or cancelled when every retained portion preserves the original food. Native portion sizes and decreasing item weight remain intact; edits that would create a replacement, near-empty remnants, custom weights and callbacks keep their protection.

### 0.1.158

- **Changed:** Wishlist row highlights now use Toolkit's shared inventory presentation boundary, removing their separate pane and CleanUI mode-switch hooks. Mixed-stack matching, full-row clipping, drag exclusions and saved settings are preserved.

### 0.1.157

- **Fixed:** Inventory search, exact categories and tag filters now match each physical item before building visible stacks. Same-name items with different individual categories no longer disappear together or satisfy different parts of one search. Category choices, selection and outgoing bulk transfers follow the resulting view in native and CleanUI inventories.

### 0.1.156

- **Changed:** The heavy Realistic Dashboard replaces its pull knob and printed label with a Polaris-style three-position headlight rocker. Its upper/lower halves step between off, low and high; distinct raised edges and recess shadows show the selection at every dashboard scale. Native headlight power commands, pending acknowledgements and external hotkey/radial changes remain authoritative.

- **Fixed:** Vehicle beam origins follow the ground projections of the current model's lamp-mask surfaces, with native normalized coordinates and per-model scale/offset. Unknown or unsupported model geometry retains upstream origins. Removed the duplicate blue headlight-switch artwork in Realistic Dashboard.

- **Fixed:** High Beams now drives the existing Realistic Dashboard lamp using its original soft artwork, dimensions and layout: green sloping rays for low and blue horizontal rays for high. Keeps warning-light fading and native power handling; the standard rotary switch cycles off/low/high with a third position and matching marking. Includes a stock-dashboard fallback.

- **Added:** Optional approximate beam geometry separates broader low beams from focused high beams and places front/reverse beam origins at the vehicle ends. Preserves upstream High Beams power/range controls, lamp colour, activation and condition scaling; can restore the original geometry.

- **Added:** Adjustable short-range light spill around working vehicle lamps, using native occlusion and cleanup when lamps turn off, lose power or leave the loaded area.
- **Changed:** With Reverse Drive Lights enabled, reverse beams default to range 12 and intensity 0.3, below native low beams (36 / 0.75). Mod Options provides weaker and original-mod presets independently of surrounding spill.

### 0.1.155

- **Changed:** Pending portions of cold food with a native cooking replacement, such as bread slices that can become toast, can be reordered or cancelled while the carried food cannot keep cooking. Original item identity, portions and cooking metadata stay intact; hot food and consumption replacements remain protected.

### 0.1.154

- **Fixed:** Better Clothing Info's main tooltip and comparison now use one measured frame for context-menu, controller and anchored placement. Its clothing details, comparison and settings remain upstream. The native per-item “No Recipes” marker is visible again and disappears when cleared.

### 0.1.153

- **Fixed:** VHS skill and recipe details now participate in native tooltip measurement and placement through the same extension boundary as planting information. Long lines and additional rows fit the tooltip background and follow its visibility. Show VHS Skills in Tooltip still supplies its catalog and translations, while its unrelated clothing suppression and background-alpha changes are avoided.

### 0.1.152

- **Changed:** Pending portions of ordinary cookable food can be reordered or cancelled once the food and its carried outer inventory are cool enough to prevent further cooking. Native cooked hunger/fullness bonuses remain intact; hot food, dangerous raw food, fertilized eggs and callback/replacement effects keep their protection.

### 0.1.151

- **Fixed:** Single-player wooden-cart emergency release starts from the last displayed held pose and finishes a short cart-only settling transition. Native instant-drop, exact cart/cargo ownership and the existing Host request remain authoritative.

### 0.1.150

- **Fixed:** Smart Deposit drag feedback and execution now use the same allocation. Items that do not fit nearby storage remain visibly rejected when other selected items can be moved. Type/category/fallback routing, protected items and native transfer actions are preserved in both inventory modes.

### 0.1.149

- **Fixed:** Distribution checks which carry containers can hold each item before reserving destination space. Items rejected by all roomy carriers no longer block later items from being sorted or push them into lower-priority overflow boxes.

### 0.1.148

- **Fixed:** Better Containers pin markers now share the actual-icon presentation used by research and planting badges. Markers follow scaled native/CleanUI icons without a separate row renderer, stay on stack headers and avoid covering other Toolkit badges; pin settings, ordering and saved data are unchanged.

### 0.1.147

- **Changed:** Pending ordinary-food actions with a captured fork or spoon use the shared queue edit contract. Safe reorder and cancellation preserve the exact selected utensil, native portion, duration and benefits; selected-tool and carried-container dependencies remain protected.

### 0.1.146

- **Changed:** Research and planting indicators now use Toolkit's shared inventory presentation in both CleanUI modes. Research availability follows native character knowledge and skills; planting information is implemented from native farming data, retaining known-season badges, growth details, crop images and saved preferences without modifying item categories.
- **Changed:** Removed the separate HasResearch and SeedSeasonIndicator mods from the selected set. Disable them in existing profiles when updating; planting settings now appear under Toolkit.

### 0.1.145

- **Changed:** Pending ordinary-food actions with any valid native portion, including EatSmart-calculated amounts, can be reordered or cancelled when their remaining-food, location and fullness dependencies permit it. Captured portions keep their original-food meaning; depleted items and required returns stay protected.

### 0.1.144

- **Fixed:** Seed Season Indicator no longer replaces inventory categories or category sorting with seasonal labels. Toolkit tags retain their normal categories; planting-season icons and detailed tooltips keep the mod's existing knowledge checks and settings.

### 0.1.143

- **Fixed:** Crafting from storage counts each physical item once when ordinary reachable containers and designated boxes overlap. The quantity limit and fetch plan share one source snapshot, so aliases cannot inflate availability or reserve the same item twice. Crafting refreshes no longer append an already accessible designated container again.
- **Fixed:** When a handcraft depends on nearby world ingredients as well as fetched storage items, the haul returns to the starting location before crafting, restoring access to those original ingredients.

### 0.1.142

- **Changed:** EatSmart menu goals use short English/Russian outcome labels, with the estimated percentage of remaining food in parentheses. Numeric targets remain in tooltips beside existing unavailable reasons; native portions, settings and callbacks are preserved.

### 0.1.141

- **Changed:** Ordinary pending food portions use the shared queue edit model, allowing legal same-item reorder and cancellation while retaining native original-food fractions. Exact pickup, remaining-food and fullness requirements protect later actions; consuming a whole item cannot precede a dependent portion or return.
- **Fixed:** Food and nutritious drinks share the character's fullness dependency. Unknown food callbacks, cooking/replacement effects and required equipment remain protected; projected consumption never grants extra container capacity or replays native effects.

### 0.1.140

- **Changed:** A wooden wheelbarrow held against an obstacle uses a planted pushing stance with staggered feet, a slight forward body lean and smooth contact/release blends. The same pose is available to other players through the existing cart synchronization.

### 0.1.139

- **Fixed:** Quartermaster distribution respects organizedCategories' enabled Stick protection. Quantity transfers preserve the original selection's intent before filtering or limiting items, so a mixed selection reduced to one item cannot bypass Stick. Deliberate single-row/stack transfers and live Stick opt-out retain their existing behavior.

### 0.1.138

- **Added:** Close an open door from the occupied seat through the vehicle radial menu (`V`) or a dashboard button. The radial uses the selected blue-door icon with a red closing arrow and artwork inset within its 64x64 canvas. The dashboard uses the native door pictogram. The filled, rounded dashboard button matches the size and hover opacity of Realistic Dashboard seat/sleep shortcuts on driver and passenger panels; it is ochre when available and grey when closed or pending. Uses the native door action and synchronization without leaving or switching seats.

### 0.1.137

- **Fixed:** Quartermaster skips matching containers that cannot accept an item while planning the haul, so a restricted or unavailable destination no longer hides the next suitable box. Explicit-item precedence, priority and planned capacity are retained; transfers still recheck the destination when executed.

### 0.1.136

- **Changed:** Toolkit now owns Container Capacity Indicator and Item Details: capacity bars, magazine segments, expanded item values and bounded stack sorting share one presentation boundary for CleanUI and native inventories. Removed both separate Workshop mods from the selected set; existing display/sort preferences are retained.
- **Fixed:** Capacity indicators follow actual scaled or texture-sized icons, and a dirty inventory redraw retains the physical Shift-selection anchor while reordering an expanded stack. Expanded food details no longer overlap Better Containers freshness percentages.

### 0.1.135

- **Changed:** Pending clean-water drinking and single-item transfers between carried containers use the shared queue edit model. Legal return/pickup orders may change the final container; removing a pickup required by a later drink remains blocked.
- **Fixed:** Modeled queue edits retain a separate capacity check using full current item weights. Native SP drink endpoints and Host consumption uncertainty are preserved; edits do not reserve future resources, alter portions or replay native effects.

### 0.1.134

- **Changed:** Wooden-wheelbarrow standing pivots use broader authored leading/following steps with modest weight transfer. The lateral stride and root-motion budget increase together, reducing foot cadence while retaining turn speed, hand grip and wheel support. Other cart types and fast gait clips retain their existing selection.

### 0.1.133

- **Fixed:** Host presets save and synchronize categories, items and tag rules as one complete snapshot, preserving existing preset identities during automatic migration. Late replies cannot restore older state, and open preset editors keep a coherent draft until save/reopen.
- **Fixed:** Storage discovery no longer rewrites container data while removing obsolete preset links. The Host container editor excludes unresolved links from its selection and cleans them through ordinary Save; SP retains world links absent from the local preset library.

### 0.1.132

- **Fixed:** Pasting container sorting settings saves categories, items, preset links, priority and tag rules together through the editor's authority checks. Stale or denied pastes leave the destination unchanged; its name, icon and colour are preserved. Removed the separate client publication of container data.

### 0.1.131

- **Changed:** Bulk clothing, electronics and battery menus share one native recipe lookup per selected item and one reachable-container snapshot per menu build. Each command retains its own first viable recipe, exact selected items and toggle; clicking still revalidates inputs and tools before queuing native actions.


### 0.1.130

- **Changed:** Pending volume, channel and microphone settings for a fixed world radio/TV can be reordered or cancelled even when they share a device. Native commands still apply each effect; the chosen order may deliberately change the final setting. Power, playback and unverified dependencies remain protected.
- **Added:** A shared versioned resource-effect contract checks the proposed queue and its downstream prerequisites. Unsupported contracts retain conservative protection, with separate required-state, resource, capacity and unknown-effect explanations.
- **Fixed:** Queue commands revalidate current ownership, operation members, generation, conditions and callbacks immediately before changing the queue, rejecting stale UI decisions without removing work.

### 0.1.129

- **Fixed:** Toolkit refreshes dependent features once after Mod Options applies all new values. Removed early per-option notifications that repeated refreshes with stale or partially applied settings; the highlight hotkey still takes effect immediately.

### 0.1.128

- **Changed:** Canceling a wholly unstarted operation with the verified native no-effect cancellation handler no longer treats shared resources with preceding work as a conflict. Dependencies of following operations, required cleanup, started work and custom cancellation handlers remain protected.

### 0.1.127

- **Added:** The first sorting tag selected in the container editor fills empty name, icon and colour fields from that tag. An exact item supplies its own icon and its primary tag's colour, leaving the name empty. Existing values and subsequent manual edits are preserved; later selections do not change the suggestion.

### 0.1.126

- **Added:** Active reading can be dragged below waiting operations, preserving their order and continuing from saved pages before returning the book to its original container.
- **Changed:** Reviewed world-TV VHS insertion supports queue edits with exact tape/device dependencies. TV power, insertion and playback retain their required order; shelf-reading moves check capacity without relying on future freed space.
- **Fixed:** In Host, VHS insertion promoted above reading tolerates its expected media/tape replication arriving before native completion, then waits for the confirmed result before advancing. After native completion, unavailable media or a bounded replication timeout skips linked playback while retaining independent reading; an unconfirmed active action retains native cancellation.

### 0.1.125

- **Changed:** World containers have one **Configure container...** editor for sorting, name, icon and colour. It reuses Better Containers' existing appearance data and icon catalogue; supported container menus no longer offer separate rename/customize paths. Bags keep their existing controls.
- **Changed:** The editor saves sorting selections, tag rules and appearance together after the same authority checks. Cancel leaves all fields unchanged; existing per-player/global Better Containers appearance is retained.

### 0.1.124

- **Changed:** Quartermaster prepares its item/tag catalog once per editor window and shares it with rule previews. Search and selection filter prepared rows instead of rescanning every loaded item; reopening refreshes the catalog. Exact picks, partial-category rules and saved categories from missing mods retain their meaning.

### 0.1.123

- **Changed:** Wishlist and crafting-plan buttons share one owner for native crafting rows and Neat Crafting footers. Creation, visibility and reserved space no longer depend on nested layout hooks; action behavior, button order and embedded-plan controls are preserved.

### 0.1.122

- **Fixed:** Better Containers pin markers now follow the inventory's rendered rows, including hidden CleanUI equipment and expanded stacks. Toolkit draws the markers directly while BC retains pin settings, menus and assets; removed the global pane swap used to install BC's separate row renderer.

### 0.1.121

- **Fixed:** Restored the reviewed Project Cook 1.4.10 action-queue integration, including batch completion and automatic dish returns. The new return producer keeps its operation ownership; changed configuration helpers remain protected.

### 0.1.120

- **Changed:** Quartermaster's owned editor now creates and handles its tag controls directly. Removed per-window method replacements for layout, filtering and controller navigation while preserving exact categories, tag rules and Save behavior.

### 0.1.119

- **Fixed:** Inventory selection follows visible rows after refresh, filtering and sorting, including hidden equipment and expanded stacks beyond the render limit. Whole-stack selections remain groups across repeated refreshes instead of becoming a single item; selection and Shift anchors share one row projection.

### 0.1.118

- **Added:** Fitness requests show exercise-specific labels and elapsed workout time in the action queue. Waiting workouts can be reordered or canceled before preparation.
- **Fixed:** Workout timers start when exercise begins. Natural endings and queue cancellation retain independent actions and restore exact carried equipment even after closing the fitness window; Host waits for the authoritative stop before advancing.

### 0.1.117

- **Fixed:** Item Details sorting keeps the Shift-selection anchor on the same visible item or group when equipped rows are hidden. Item Details and Better Containers now share row mapping for collapsed equipment, virtual stack headers and clipped stacks.

### 0.1.116

- **Changed:** Quartermaster exposes distant storage only during crafting-panel container refreshes for the requesting player. Removed the render-time global availability window; ordinary inventory queries and fallback crafting keep their normal containers, while ingredients still travel through the existing physical haul.

### 0.1.115

- **Changed:** With item tags enabled, Quartermaster category and tag selections exclude broken tools, including carpentry tools. Explicit item assignments can still collect them.
- **Fixed:** The `drug` tag uses the native pill icon instead of a suture needle.

### 0.1.114

- **Fixed:** Tag choices and previews use organizedCategories inventory categories while preserving native loot categories. Quartermaster prepares item categories directly before sorting, inspecting container contents and recording the storage manifest, removing dependence on prior inventory-pane refreshes or external wrappers.

### 0.1.113

- **Fixed:** `Distribute Loot` remains available when right-clicking an item in the inventory or a worn bag, even when its toolbar button is visible. Explicit menu-profile hiding remains respected.

### 0.1.112

- **Fixed:** Walking no longer loses the queued action after an item finishes transferring from a carried bag. Belt attachment, drinking and other follow-up actions retain their native movement and cancellation rules.

### 0.1.111

- **Fixed:** Grab and Grab One work when organizedCategories and Tidy Up Meister are loaded. The compatibility guard now uses the shared closure check instead of calling a removed helper before the pickup starts.

### 0.1.110

- **Changed:** Quartermaster's owned editor and clipboard save complete container designations directly, without callback interception or temporarily replacing the clipboard. Native fields are published together after any tag-rule acceptance; existing save data and authorization are preserved.
- **Fixed:** Copy/paste preserves preset generations, preventing a copied link from silently attaching to a deleted-and-recreated preset with the same name.

### 0.1.109

- **Fixed:** Inspecting clothing from storage uses the item delivered to the player's inventory in Host/multiplayer, keeping the inspection window open after transfer. Delayed cart deliveries get a bounded wait; carried-item and single-player inspection retain the native window.

### 0.1.108

- **Fixed:** The action queue window remembers each local player's moved position when the native queue is replaced or disappears during the current game session.

### 0.1.107

- **Changed:** E picks up the nearest reachable cart or puts down the held cart. Accepted cart actions take priority over doors and windows for that key press; ordinary Interact remains available when no cart action starts. The old V default migrates once, preserving other custom bindings.

### 0.1.106

- **Changed:** Quartermaster preset commands use owned storage directly, saving presets and tag rules together without replacing global functions or publishing temporary drafts. Existing saved formats, legacy import and multiplayer commands are preserved; the unused duplicate parser is removed.
- **Fixed:** The multiplayer startup retry waits for both preset data and enabled tag rules, matching the sorting readiness check.

### 0.1.105

- **Fixed:** Waiting native drinks from independent inventory bottles can be cancelled or reordered, including verified SaucedCarts wrappers. Clean-water backpack operations retain conservative capacity checks. Active drinking, shared bottles and unknown callbacks remain protected; vanilla portion calculations are unchanged.

### 0.1.104

- **Changed:** Quartermaster is included in Toolkit with its storage designations, distribution, Manifest and crafting integration. Disable the separate Workshop mod when updating; existing assignments, options and presets keep their identifiers and formats.
- **Changed:** Container tag rules pass directly to sorting instead of temporarily replacing item categories. Craft-window layout and action-queue handoffs are integrated with the owned implementation.

### 0.1.103

- Register bounded cart locomotion and interaction snapshots for native multiplayer variable synchronization; every client renders cart poses locally.
- Align the final wooden wheelbarrow pickup approach with the center between its handles.

### 0.1.102

- **Fixed:** An updated Project Cook interface no longer prevents TidyUpMeister from preserving explicit equipment choices. Independently verified recipe modifiers load before compatibility snapshots; changed cooking interfaces and unknown modifiers remain protected.

### 0.1.101

- **Fixed:** Queue transfer controls recognize Better Containers 42.21 and its new stale-vehicle helper. Modified helpers remain protected, and transfers into stale vehicle containers retain the upstream rejection.

### 0.1.100

- **Changed:** Wishlist uses Toolkit's shared button styling and inventory-class integration, removing duplicate standalone paths while preserving existing controls and highlights when CleanUI switches views.
- **Fixed:** Better Containers pins remain first within their search and equipment sections across native, CleanUI and organizedCategories inventory views, preserving selection and the chosen column order. Added under this existing version label in `2dd301c`.

### 0.1.99

- **Fixed:** Wishlist, tag-rule, context-menu and craft-chain labels share Unicode-safe truncation. Long labels preserve whole characters in the game's native string format, and very narrow columns no longer show an overflowing ellipsis.

### 0.1.98

- **Fixed:** Closing the context-menu editor or tag-rule picker releases text-entry focus and its open dropdown, including when the feature is disabled or settings cannot be saved.
- **Fixed:** Window cleanup, including Wishlist, leaves another control's shared dropdown open.

### 0.1.97

- **Changed:** Audited TidyUpMeister cleanup of temporarily held items uses shared native completion, preserving empty hands, exact inventory returns and explicit equipment intent. Clothing, hotbar, heavy items and unverified callbacks retain their existing completion path.

### 0.1.96

- **Changed:** Wishlist sharing now searches and selects online players instead of accepting typed usernames. Existing offline members keep their access.

### 0.1.95

- **Fixed:** Server medicine throttles discard expired player entries, and Wishlist refreshes release disconnected players' snapshots and request buckets without relying on weak tables unsupported by Kahlua.

### 0.1.94

- **Fixed:** TidyUpMeister can return borrowed floor items in Host after the network replaces their inventory reference, preserving exact item identity, original placement and explicit pickup intent with the queue enabled or disabled.
- **Changed:** Audited TidyUpMeister hand and activation restores use shared native completion, preserving protected mixed-session cleanup. Equipment slot and floor placement fields are checked before granting queue permissions.

### 0.1.93

- **Changed:** Audited TidyUpMeister inventory returns retain their queue contracts after approved late transfer hooks and use shared native completion ownership, preserving exact destinations, explicit pickup/equipment intent and the unsupported-engine fallback.

### 0.1.92

- **Changed:** Audited medical expansion uses shared native completion ownership, retaining exact child treatment/resource proofs, bare-hands ordering and the unsupported-engine fallback.

### 0.1.91

- **Fixed:** Prepared mods and developer ZIPs retain the common/version animation and action-group directories required by native Host loading, avoiding missing-directory errors that the test snapshots previously masked.

### 0.1.90

- **Changed:** Generator repair chains use shared native completion ownership while preserving exact repair effects, continuation guards and the unsupported-engine fallback.

### 0.1.89

- **Changed:** Campfire kindling retries use the shared native completion boundary while retaining exact child validation and retry-before-tool-return ordering. Unsupported engines keep the existing completion fallback.

### 0.1.88

- **Fixed:** Context-menu preferences use alternating checked snapshots with readback verification, retain the legacy INI for import and refuse stale writes. Failed loads cannot overwrite saved settings; failed preference edits roll back without reporting success. Reopening the editor retries in the same profile object, and storage failure leaves ordinary menus usable.

### 0.1.87

- **Fixed:** Fullness no longer silently cancels water drinking after a backpack transfer. Empty containers remain invalid; nutritious drinks keep their native fullness restriction. Applies in single-player and Host, with or without the Toolkit queue.

### 0.1.86

- **Fixed:** Wishlist and named inventory tag filters refuse writes when the game cannot open/read/close their existing stores. Fresh empty slots initialize safely and failed loads retry without caching an empty replacement; Wishlist directory creation never truncates an existing slot.

### 0.1.85

- **Fixed:** Single-player Quartermaster presets and Toolkit tag rules save as one verified snapshot, alternating between two files. Interrupted or short writes retain the previous coherent pair; failed verification forces a fresh read before another save. Existing global files import automatically and remain untouched.
- **Fixed:** Preset snapshots preserve native generation, revision, creator and item full types across restarts. Strict parsing rejects malformed or trailing data; string quoting preserves backslashes, Unicode and control characters in the game's Lua runtime.

### 0.1.84

- **Fixed:** Server-side cart unequip and broken-cart drop finish without accessing the client action queue and return a Boolean based on the authoritative item result.

- **Fixed:** Server cart pickup reconstructs the selected action without querying client render models.
- **Fixed:** Cart pickup retains the constructor field names required by native multiplayer serialization, so Host/server actions receive the cart coordinates and ID for every cart type.
- **Fixed:** Repeated wooden-wheelbarrow pickup uses fractional stance distance rather than the integer-only distance overload, avoiding an unnecessary zero-length path and cancelled pickup.

- **Fixed:** Shopping carts and metal wheelbarrows approach an accessible adjacent tile before ground pickup when out of reach. Native pickup/equip, cargo and the wooden-wheelbarrow stance are preserved.

### 0.1.83

- **Fixed:** Quartermaster waits for both its presets and Toolkit tag rules before multiplayer sorting, and requests both again through its existing gather retry when either is missing. Disabling tags retains native readiness.
- **Fixed:** Failed single-player tag-rule reads no longer publish an empty cache or allow linked native preset changes before loading succeeds. Readers/writers close on exceptions; serialization finishes before opening the existing file for overwrite.

### 0.1.82

- **Added:** Wishlist requests for compatible vehicle parts from the mechanics window. All compatible variants of the requested vehicle class are highlighted in inventories and mechanics, with combined carried counts.
- **Changed:** Item context menus and the catalog switch between adding and removing requests. Compatible vehicle groups have their own removal actions, preserving separate exact-item requests and the selected list.

### 0.1.81

- **Fixed:** Better Generator Info queue integration accepts its reviewed source in the game as well as the test runtime. Source checks now share UTF16 normalization, bounded reads and reader cleanup across compatibility, fire, generator and medical adapters; changed or unverified sources remain protected.

### 0.1.80

- **Fixed:** Verified native crafting UI batches skip an exhausted pool of selected one-use items before the next craft starts, preserving tool cleanup and independent queued actions. A sufficient remaining pool continues normally.

### 0.1.79

- **Fixed:** Shared transfer guards preserve existing completion callbacks and their arguments. Reapplying the guard retains native stop provenance without granting unknown callbacks queue permissions.

### 0.1.78

- **Fixed:** Bulk clothing cutting includes belts, eligible holsters and empty bandoliers through the native recipe, including mixed selections with clothing. Native tools, outputs and protected-item checks are preserved.

### 0.1.77

- **Fixed:** Clicking inventory items during transfers follows the pressed item across row changes and stack sorting instead of selecting the replacement row on mouse release. Rapid clicks on different items no longer trigger a double-click action after a transfer.

### 0.1.75

- **Changed:** Lemongrass displays the native cooldown instead of estimating its maximum duration. Removed the separate Lua countdown and food-action hooks; unsupported readings hide only this indicator.

### 0.1.73

- **Added:** Authored wooden-wheelbarrow pickup and setdown clips, including the SaucedCarts setdown hotkey, cancellation recovery and exact world/held-item handoffs.
- **Fixed:** Brief transitions from Run/Sprint to walking retain cart momentum for smooth, cargo-dependent braking.
- **Changed:** Consolidated the cart integration with the current queue and shared Wishlist changes; remote cart-pose reconstruction and the remaining visual cases stay open.

### 0.1.72

- **Fixed:** Automatic batch crafting keeps automatic material selection without the B42.21 Java queued-item accounting exceptions. Manual selection and native multiplayer constructor fields are preserved.

### 0.1.71

- **Fixed:** Native crafting UI actions remain supported when Quartermaster or P4 wraps layout and craft-button entry points. Neat accepts only the two source-verified Quartermaster UI wrappers; completion, cancellation and their helpers retain identity guards.
- **Fixed:** Project Cook batch crafting releases its per-action busy counter after every completed craft, so its window becomes available again when the batch ends.

### 0.1.70

- **Fixed:** Before a queued manual craft starts, a missing selected input cancels only its operation and preserves safe tool returns and independent follow-up work. Started crafts and unknown callbacks keep their existing safeguards.

### 0.1.69

- **Fixed:** Queue reset and clear revoke pending callbacks through the shared native cancellation boundary, including after Quartermaster reloads its saved reset wrapper. Clearing only a command's generated actions preserves its parent and valid continuations.

### 0.1.68

- **Fixed:** A completed multiplayer fire ignition waits for its correlated server outcome before cancellation cleanup, preserving the original fuel container and queued follow-up actions.

### 0.1.67

- **Fixed:** Queue behavior lookup evaluates only handlers registered for an action's type; an unrelated handler failure no longer disables other families. Matching errors and ambiguous contracts still deny control.
- **Changed:** Move, cancellation and priority checks share lazy analysis within one decision and refresh resources and helper validation on the next decision.

### 0.1.65

- **Changed:** Wishlist is included in Toolkit, with one ground-item scanner and sidebar entry. Existing lists and settings retain their identifiers and format. Remove the old Wishlist mod folder and Mod ID when updating; keep its saved data.


### 0.1.61

- **Changed:** Added cargo-dependent cart acceleration/steering, distinct shopping-cart and wheelbarrow turns, and rolling wheel contact.
- **Changed:** Refined the wooden wheelbarrow's anchored grip, natural Walk/Run/Sprint legs, 7-degree turn lean, backward steps and forward/reverse transitions.
- **Fixed:** Smoothed heavy-item braking and the final return to the standing grip, preserving immediate input interruption and hand contact.
- **Note:** Remote cart-pose reconstruction, stationary turns and natural pickup/put-down remain unfinished; these local animation changes do not establish multiplayer equivalence.

### 0.1.58

- **Fixed:** Preserve the verified SP transfer chain when Quartermaster Manifest and SaucedCarts are both enabled.
- **Added:** Guarded native inventory bandaging, including carried-bag pickups, with exact selected items and self-treatment targets.
- **Added:** MiniHealthPlus bandage replacement is one queue operation across removal, pickup and application. Cancellation preserves completed effects and borrowed supplies; lost future materials stop replacement before removing the current bandage.

### 0.1.57

- **Fixed:** First drops of ready-made and handmade splints enqueue treatment with the exact dropped supplies, preserving native clinical restrictions and earlier handlers.
- **Added:** Guarded MiniHealthPlus treatment queue operations with a stable doctor/patient, cancellation and reordering. Bandage replacement and direct inventory-menu treatment remain protected.
- **Fixed:** Preserved reviewed container-getter chains after Quartermaster installs its crafting wrapper; active remote-storage availability scans remain protected.

### 0.1.56

- **Fixed:** Planting inputs such as sunflower seeds, potatoes and herbs gain Farming/Seed tags while preserving their food/medical roles; empty seed packets keep Farming without Seed. Roles come from native crop definitions and seed-packet recipes.
- **Fixed:** Inventory filters, previews and Quartermaster tag rules match individual items, including mixed-category stacks; unrelated items sharing a category or display name are not included. Partial-category tag selections use stable rules across UI languages; manual Quartermaster category/item selections remain additive.

### [0.1.55](https://github.com/AlexRedby/pz-survivor-toolkit/commit/7755743)

- **Added:** Native icons for all 209 defined tags, with shared caliber pictograms and a generic icon for custom categories.
- **Fixed:** Completed known installed category mappings, including the exact `FurnitureDoor` alias; preserved existing exact-category filters after semantic tags are added.
- **Added:** An explicit-source category coverage checker.

### [0.1.54](https://github.com/AlexRedby/pz-survivor-toolkit/commit/e689236)

- **Added:** Combined all/any tag filters with exclusions, grouped search, match previews and named local saved filters.
- **Added:** Persistent Quartermaster container/preset tag rules with server validation, stale-write rejection and peer synchronization; manual selections remain additive.

### [0.1.53](https://github.com/AlexRedby/pz-survivor-toolkit/commit/72b97cdba2399950e24bc76ab9d048519c560eef)

- **Added:** Native pictograms and consistent item-family colours for item tags, including Quartermaster tag choices and inventory chips.
- **Changed:** Combined tag visuals with the medical queue operations from the parallel 0.1.52 snapshot.

### [0.1.52](https://github.com/AlexRedby/pz-survivor-toolkit/commit/7e406a542f4ceff7ea17cba3c7e3eeab8b9836c0)

- **Added:** Localized item tags derived from organizedCategories, inventory tag chips/filters and tag-based Quartermaster selection while preserving exact legacy category IDs.
- **Added:** Guarded native medical queue operations with doctor/patient and wound identity, independent treatment reordering, supported active cancellation and borrowed-tool returns. [Medical source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/1ea939076d6c96be6c1204c0f213486f435a585b).
- **Note:** The tag and medical changes used the same version label on parallel branches; their combined snapshot is 0.1.53.

### [0.1.51](https://github.com/AlexRedby/pz-survivor-toolkit/commit/cc2fb6744d857b23406c7bb43c70798c6447d5ae)

- **Added:** Capacity-aware reordering and cancellation of independent carried-cart transfers, including cart-to-cart routes; shared cargo and in-flight multiplayer transfers remain protected.
- **Changed:** Expanded generator fuel/pickup and fire-operation compatibility with reviewed equipment helpers; holding a cart retains conservative controls.

### [0.1.50](https://github.com/AlexRedby/pz-survivor-toolkit/commit/f2072566509dd919ab5a16adeebcd27d1baa157b)

- **Added:** Queue-aware Better Generator Info connection and power controls, preserving dependencies between shared power areas and buildings.

### [0.1.49](https://github.com/AlexRedby/pz-survivor-toolkit/commit/88590522d1d0dcad9af8bd99bdcfbe13c9eb8634)

- **Fixed:** Kept queued washing/drying attached to the correct live clothing and towel IDs when multiplayer replaces item objects.
- **Fixed:** Skipped returns of already-consumed fire inputs without losing borrowed tools or unrelated queued work.

### [0.1.48](https://github.com/AlexRedby/pz-survivor-toolkit/commit/a083a49a530d4f9eee6c499804d36e08fe161986)

- **Added:** Queued opening and eating for native OpenCannedFood/OpenCannedFood2 recipes, linking full/half/quarter portions to the exact created food item.
- **Fixed:** Prevented late or duplicate results from restarting cancelled eating or consuming unrelated food.
- **Fixed:** Released completed operation records and closed crafting UI owners/listeners instead of retaining them indefinitely.

### [0.1.47](https://github.com/AlexRedby/pz-survivor-toolkit/commit/f26fa4fc610f2842682fdf2ff91d8cd71fd0bee2)

- **Added:** Half and quarter portions for selected-food batches.
- **Changed:** Allowed independent washing and towel-drying operations to move or cancel safely; active native effects and resource use finish before cancellation of later steps.

### [0.1.46](https://github.com/AlexRedby/pz-survivor-toolkit/commit/70513065c473f762a2f61b0f0c26eb521aedac65)

- **Changed:** Matched cart body/hand animation speeds and transitions, and added load-dependent walking turns. Running/sprinting keep native steering; releasing the cart restores ordinary handling.

### [0.1.45](https://github.com/AlexRedby/pz-survivor-toolkit/commit/3bcc56fcab6c8b916fe18759cf38e511c7f686ce)

- **Changed:** Restricted shopping-cart spawns to appropriate retail/warehouse surroundings while retaining wheelbarrows around farm/shed storage. Existing carts and saved spawn decisions are preserved.

### [0.1.44](https://github.com/AlexRedby/pz-survivor-toolkit/commit/2b5d89843512e34e5e50048918189302fcad2d42)

- **Changed:** Combined the guarded cart queue controls and the unsupported-resource inspection fix from the parallel 0.1.43 snapshots.

### [0.1.43](https://github.com/AlexRedby/pz-survivor-toolkit/commit/8a6a28c437ba2dbe7f7856f9bc9fe48316a2e47b)

- **Added:** Guarded queue controls for carried-cart transfers and native single-player cart returns.
- **Fixed:** Restored recursive single-player generator repair across native completion/cleanup boundaries.
- **Fixed:** Stopped unsupported craft/repair inspection from emitting caught-assertion errors; unknown resources remain protected. [Inspection fix](https://github.com/AlexRedby/pz-survivor-toolkit/commit/ae3cb58d62855f5703d6ed353e2a5670f37e8a17).

### [0.1.42](https://github.com/AlexRedby/pz-survivor-toolkit/commit/6bc32bcf69ebe6275f24a831161ab94054547c82)

- **Changed:** Combined queued bulk eating with the Item Details and cart-equipment fixes from the parallel 0.1.41 histories.

### [0.1.41](https://github.com/AlexRedby/pz-survivor-toolkit/commit/8f6c44dcac8535d85278a4977879667ddf5e00de)

- **Added:** Eat selected batches for eligible ready-to-eat food, with exact item ownership, favourite-item exclusion and independent cancellation.
- **Changed:** A parallel snapshot combined the Item Details and cart-equipment fixes from 0.1.40. Both histories were combined in 0.1.42. [Integration source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/ce52f5537cb897a88a8faebeeb68356dc1b02370).

### [0.1.40](https://github.com/AlexRedby/pz-survivor-toolkit/commit/433ef33fab238496318178b547c7d97a09b2c3fa)

- **Fixed:** Restored Item Details condition display/sorting for organizedCategories vehicle parts and preserved every item beyond the configured sorted prefix of large stacks.
- **Fixed:** Cleared stale cart hand slots after Tidy Up Meister cancellation and recognized server-completed multiplayer cart pickup/equip. [Cart fix](https://github.com/AlexRedby/pz-survivor-toolkit/commit/8aa02a9cebf16ae6d762ecb02622599b3c65167b).

### [0.1.39](https://github.com/AlexRedby/pz-survivor-toolkit/commit/a28ad9ccf454c9406c6977f2b3b6f083cc0a612a)

- **Fixed:** World-electronics dismantling no longer discards following work when multiplayer removes the target before the action completes.
- **Fixed:** Deduplicated the same physical vehicle part exposed through both proximity and real containers. [Vehicle fix](https://github.com/AlexRedby/pz-survivor-toolkit/commit/74b924028af5b4380a29d23a7feb7b5817024801).

### [0.1.38](https://github.com/AlexRedby/pz-survivor-toolkit/commit/02593124e27b4e184b334da1b8f914d963ee86be)

- **Added:** Guarded generator and camping/BBQ/fireplace fuel/lighting queue operations, including recursive generator repair, cancellation and borrowed-tool returns.

### [0.1.37](https://github.com/AlexRedby/pz-survivor-toolkit/commit/4a7c270d676ea243394d6172589fdcca7c21f57a)

- **Fixed:** Initialized SaucedCarts drop, unequip and forced-drop safety hooks on dedicated servers, preserving worn-cart cargo and preventing stale hand references from duplicating a ground cart.

### [0.1.36](https://github.com/AlexRedby/pz-survivor-toolkit/commit/ade2c97fc9d04823e694f6a0f1a4ee4e3c9b4581)

- **Added:** Independent transfers through nested carried bags with capacity checks across destination ancestors.
- **Changed:** Single-player capacity checks can account for space freed by a required earlier pickup; multiplayer and unknown capacity effects remain conservative.

### [0.1.35](https://github.com/AlexRedby/pz-survivor-toolkit/commit/ca7efdeb1165527f4254279f9e32304ef737f627)

- **Added:** Reordering/cancellation of independent carried-bag transfers when the proposed order fits available capacity.
- **Fixed:** Kept mixed Tidy Up Meister returns attached to the correct operation while preserving shared equipment cleanup.

### [0.1.34](https://github.com/AlexRedby/pz-survivor-toolkit/commit/c5e33f53e6216239a0458ceb3c4bfac5ba5b623a)

- **Changed:** Expanded safe queue controls to known future craft inputs and supported WashFix, Neat Equipment, Tidy Up Meister and Project Cook continuations; unknown callbacks retain protected controls.
- **Changed:** Stove power requests take priority at safe boundaries, preserve reading and revalidate the desired state instead of toggling twice.
- **Added:** Localized presentation for native action families, separate from their movement/cancellation permissions.

### [0.1.33](https://github.com/AlexRedby/pz-survivor-toolkit/commit/3a3675767f2b0ebe153a537f93030f1b4b0c0442)

- **Added:** Queued burnt/smashed vehicle dismantling without interrupting prior work, with tools/targets rechecked when execution begins.

### [0.1.32](https://github.com/AlexRedby/pz-survivor-toolkit/commit/ae35a65595b0f55a3793125cbc0645e06d62379a)

- **Fixed:** Vehicle refuelling and siphoning select containers and calculate amounts when their turn begins, allowing repeated requests to use the next eligible container without dropping later work.

### [0.1.31](https://github.com/AlexRedby/pz-survivor-toolkit/commit/6f4a3eb5be4f990c39f739cd1bbfe89c10d9d778)

- **Changed:** Grouped native/Neat multicraft and legacy Craft All batches with meaningful progress and cancellation of future continuations.
- **Fixed:** Appliance controls no longer discard unrelated queued work; approach and target validation are deferred until execution.

### [0.1.30](https://github.com/AlexRedby/pz-survivor-toolkit/commit/f7de4db558b526e0fe55e4e2457230016af33a2f)

- **Added:** Safe multiplayer construction interruption/resumption with server acknowledgements from Java Patches 0.1.3; completed builds are never replayed.
- **Changed:** Allowed waiting item repair to cross independent work while protecting matching future donors and shared dependencies.

### [0.1.29](https://github.com/AlexRedby/pz-survivor-toolkit/commit/b3eef8a4b957300e30e7c5f285e02a0bd6694e93)

- **Added:** Supported active operation cancellation and independent native/Neat handcraft reordering, preserving completed results and eligible borrowed-item returns.
- **Fixed:** Sidebar icons no longer intercept native Cooking flyout clicks. [Sidebar fix](https://github.com/AlexRedby/pz-survivor-toolkit/commit/2bfa133af39afda263fe67c1754cef87da460121).

### [0.1.28](https://github.com/AlexRedby/pz-survivor-toolkit/commit/c7cc5f17a49fa95d2bfe483e1c52006b13d6a47c)

- **Added:** Prerequisite crafting plans for native and Neat Crafting: reachable-stock accounting, reusable tools, intermediate chains, material choices and queueing as one operation.
- **Changed:** Combined crafting plans with whole-operation queue controls and the compact sidebar. This is the first retained source snapshot of the planner; the older README also calls it 0.1.27.

### 0.1.27 (documented label)

The older README associates prerequisite crafting with this label, but no separate 0.1.27 metadata snapshot is retained. See [0.1.28](#0128) for the committed planner changes.

### [0.1.26](https://github.com/AlexRedby/pz-survivor-toolkit/commit/07bbc747bc18a5fa0acf1a35762ea61048f2d773)

- **Changed:** Improved EN/RU task labels and target headings, preserving operation titles during preparation and returns.
- **Changed:** Extended whole-operation cancellation and deferred world-action preparation. [Operation source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/2d2175936d7a1f32874552630148a9d4cc923a9d).
- **Changed:** Replaced sidebar squares with compact flashlight/tools icons, settings shortcuts and matching window controls. [Sidebar source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/9c0dcb22e6444ccf7b289ac712c7b3bc9c413dac).

### [0.1.25](https://github.com/AlexRedby/pz-survivor-toolkit/commit/17aac2f10643ca5c8999df8048df3b36615951f6)

- **Added:** Collapsible operation groups with expandable native steps and whole-operation dragging/cancellation.
- **Fixed:** Prevented unsafe movement across shared world targets and dependent preparation/return steps.

### [0.1.24](https://github.com/AlexRedby/pz-survivor-toolkit/commit/a88007511440e3ec01857c98ab12eaa525191231)

- **Changed:** Ordered common context-menu actions by purpose and context, while preserving stable ties, unknown commands, manual placements and native selectors.

### [0.1.23](https://github.com/AlexRedby/pz-survivor-toolkit/commit/ec25437cf747e0bde37c877329687f12acc83b8d)

- **Fixed:** Removed exact repeated context-menu commands and duplicate bulk entries while preserving different targets, arguments and mod metadata.

### [0.1.22](https://github.com/AlexRedby/pz-survivor-toolkit/commit/d539d45b8eabc3a5d17654c181c8b0e6caf41de0)

- **Added:** Cut selected clothing for mixed cotton, denim and leather, using native recipes/tools and skipping favourites and worn/held garments.

### [0.1.21](https://github.com/AlexRedby/pz-survivor-toolkit/commit/eee693878b6bfe4ad1a420780ea7bac503c1ac7b)

- **Added:** Automatic context-menu groups and editable per-player rules for placement, hiding and restoring actions.
- **Changed:** Enabled the action queue on fresh profiles and allowed whole waiting operations to move ahead of reading and resume it afterwards. [Queue source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/665ee8b973e2b3809a59e6cb4cf0824f4c57fca1).
- **Added:** Deferred door dismantling and selective cancellation without clearing unrelated work. [World-action source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/3a0a88bc1304ebf6fd54fe77e24709bf6afb63f7).
- **Changed:** Added Wishlist-aware ground-highlight priority and preparation/distribution of the complete three-component set. [Wishlist integration](https://github.com/AlexRedby/pz-survivor-toolkit/commit/668b867e30ca174e7144ab944938923ee4aaa99c) and [distribution source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/5808f1329403409f359abd2d6310f4e32d242933).

### [0.1.20](https://github.com/AlexRedby/pz-survivor-toolkit/commit/0ba9f52ad0ff19d658be3711ffdadc9616dc5f97)

- **Added:** Grab amount / Put amount with a whole-number budget across a selected batch.
- **Changed:** Provided medicine/herb indicators directly through MoodleFramework, removing the Medicine Moodles dependency and preventing duplicate indicators.
- **Fixed:** EN/RU TV device recognition, Better Containers category-filter integration and malformed MP Fast Forward speed commands.
- **Added:** Optional native action-queue window with icons, per-row cancellation and guarded drag reordering. [Initial queue](https://github.com/AlexRedby/pz-survivor-toolkit/commit/9756eccd63e8b4e9912c533522a80f126d7ab981) and [row controls](https://github.com/AlexRedby/pz-survivor-toolkit/commit/6ed594650371ee1b54af058bfe1077fbdd0c46a4).

### [0.1.19](https://github.com/AlexRedby/pz-survivor-toolkit/commit/74cb8b717dde00fa26522de03d75b5a062bd71a0)

- **Added:** Bulk battery removal, magazine/firearm unloading and weapon-attachment removal with native tools, outputs and item identities.
- **Changed:** Corrected server-derived medicine effects and added independent herbal indicators, including dried herbs. The older README refers to this medicine work as 0.1.16; this is its first retained source snapshot.
- **Changed:** Fitted Navigator to vanilla/Realistic Dashboard styles with a compact textured housing and live rollback.

### 0.1.16 (documented label)

The older README associates medicine indicators with this label, but no separate 0.1.16 metadata snapshot is retained. See [0.1.19](#0119) for the committed medicine changes. No distinct functional record for 0.1.17 or 0.1.18 is retained.

### [0.1.15](https://github.com/AlexRedby/pz-survivor-toolkit/commit/d9ebdf52419187ce4520cfac67074d7dd4882dc5)

- **Changed:** Combined vehicle-part removal to the ground with bulk electronics dismantling and contested-pickup protection.

### [0.1.14](https://github.com/AlexRedby/pz-survivor-toolkit/commit/449337180d795f94f747d20a0176d0c7c7050fac)

- **Fixed:** Preserved native dismantling recipe icons/submenus and stopped rejected bulk pickups from cancelling another client's same-numbered transaction.

### [0.1.13](https://github.com/AlexRedby/pz-survivor-toolkit/commit/8fbb425f1bd49bdbadd4cde81e5f3fe057fe3881)

- **Added:** Optional bulk dismantling of selected electronics with native recipes, tools, outputs and XP.
- **Added:** A parallel 0.1.13 snapshot added Uninstall to ground for removable vehicle parts, preserving native tools, duration and success/damage chances. Combined with bulk dismantling in 0.1.15. [Vehicle source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/88ee47cc4a939eb99bd31a6b8ab2c0344d122d1f).

### [0.1.12](https://github.com/AlexRedby/pz-survivor-toolkit/commit/b5bdd893b273a2658e6e369aec5299794059f141)

- **Fixed:** Kept CCI item/container-button bars working across CleanUI enhanced/vanilla modes and icon views, including native icon alpha.

### [0.1.11](https://github.com/AlexRedby/pz-survivor-toolkit/commit/195b5bc82a4786243a1f4ebd34bc52fef1caf0bb)

- **Fixed:** Preserved manually selected Proximity Inventory loot containers across automatic source/destination selections without bypassing native container locks.

### [0.1.10](https://github.com/AlexRedby/pz-survivor-toolkit/commit/9b9f5410a9a7bf5e00443f6b374db7a201c1150d)

- **Fixed:** Preserved inventory marquee selection across refreshes.

### [0.1.9](https://github.com/AlexRedby/pz-survivor-toolkit/commit/a1efc520c0feeffa221faffd670cedcf2e89ec03)

- **Added:** Inventory category filters.
- **Fixed:** CleanUI inventory layout integration and Manage Containers controls in both enhanced and vanilla inventory modes.

### [0.1.8](https://github.com/AlexRedby/pz-survivor-toolkit/commit/896ff3526ce0ed8a12368aedc6f4f9dbab8a0b00)

- **Fixed:** Marked only fully watched VHS tapes as completed for the current character.

### [0.1.7](https://github.com/AlexRedby/pz-survivor-toolkit/commit/7a0fbcd204663f4bbdd3c00070fec86cd5de288d)

- **Added:** VHS selection from reachable containers/bags, drag insertion and direct click-to-eject using native inventory/device actions.

### [0.1.6](https://github.com/AlexRedby/pz-survivor-toolkit/commit/7b62819b8e758a4e9d15d19cba231a7559eebea6)

- **Added:** Independent switches for the sidebar highlight button and neutral clothing comparisons.

### [0.1.5](https://github.com/AlexRedby/pz-survivor-toolkit/commit/7b8b438399f578208144b11413a38b7eba229cd9)

- **Fixed:** Hid optional-mod settings and skipped their integrations when the corresponding mod was inactive.

### [0.1.4](https://github.com/AlexRedby/pz-survivor-toolkit/commit/c4f86df469bc8a9fb3083a632b4310dfafa81037)

- **Added:** Configurable TV/radio window persistence and native macOS video lookup in the active TV mod directory, without a Workshop-path symlink.

### [0.1.3](https://github.com/AlexRedby/pz-survivor-toolkit/commit/1cad3f4b24e3d8bbecb44f9f5b23d16b9c6749a8)

- **Fixed:** Aligned Container Capacity Indicator bars with CleanUI inventory rows, equipment headers and scaled icons.

### [0.1.2](https://github.com/AlexRedby/pz-survivor-toolkit/commit/e91b9225d7fbc3e2a12c952f268f74f819752377)

- **Fixed:** Used each multiplayer player's auto-drink preference instead of the host's saved global option, including option reloads.

### [0.1.1](https://github.com/AlexRedby/pz-survivor-toolkit/commit/6d23b177b9661102e02fdd2ca5c8c2dc5f562b2e)

- **Changed:** Displayed zero clothing-protection differences in neutral grey while retaining native improvement/degradation colours.

### [0.1.0](https://github.com/AlexRedby/pz-survivor-toolkit/commit/3926508d2d421ddc021aef1032f914e335eec95d)

- **Added:** Visible loose-item highlighting, native Mod Options for colour/radius/shortcut, an F8 shortcut and sidebar toggle.
- **Added:** Mod icon and localized selection metadata.

## Survivor Wishlist

### [0.1.0](https://github.com/AlexRedby/pz-survivor-toolkit/commit/668b867e30ca174e7144ab944938923ee4aaa99c)

- **Added:** Independent personal and shared wishlists, with a searchable item catalog, desired quantities, carried-item counts and manual completion.
- **Added:** Shared editing for named players or a faction, owner-controlled access, revision-conflict protection and persistent lists separated by world.
- **Added:** Inventory-menu and native/Neat Crafting/Neat Building/Project Cook integration for adding wanted items, recipe results and missing ingredient choices.
- **Added:** Highlight wanted inventory rows and visible loose ground items, with CleanUI and Better Containers support and independent highlight/crafting settings.
- **Added:** English and Russian UI, a configurable K shortcut and sidebar access.
- **Changed:** Replaced the standalone sidebar text button with a compact tools icon, integrated Wishlist access into Toolkit's sidebar menu and matched button styling.
- **Fixed:** Prevented the standalone Wishlist sidebar icon from blocking the native Cooking flyout's clicks, and kept the icon aligned with sidebar visibility and scaling.

## Toolkit Java Patches

### 0.1.73

- Preserve exact drainable charge during multiplayer item-stat synchronization, including native rounded-full values. Batteries and other drainable items no longer lose charge through the receiver's float conversion; invalid payloads and unsupported game versions retain native handling.

### 0.1.72

- Add a guarded makeup-avatar overlay that copies visual fields without changing inventory, clothing, gameplay visuals, random state or network packets. Unsupported native layouts keep the existing preview path protected.

### 0.1.71

- Expose current covered-part laundry stains without initializing item visuals, drawing random values or changing item state. Unsupported native metadata remains unknown.

### 0.1.70

- Expose read-only initial fluid amount bounds for category previews, including default-full, fixed, empty and ranged definitions. Unsupported native metadata remains unknown without creating items or drawing random values.

### 0.1.69

- Expose read-only native script bandage and alcohol power for medical tag previews. Missing or unsupported metadata remains unknown; the helpers do not create items or modify game state.

### 0.1.68

- Expose read-only recipe creation-handler metadata so cooking tags recognize native milk-powder recipes without executing them or accepting a replaced handler.

### 0.1.67

- Expose read-only native Eat-menu and recipe item-test metadata for accurate tag previews. Unsupported bytecode returns unknown; neither helper creates items or executes recipe callbacks.

### 0.1.66

- Expose native script wear slots and writing capability through read-only Lua helpers, so item-tag previews distinguish wearable bags and blank writing materials without creating inventory items or requiring debug mode.

### 0.1.65

- Provide a read-only, ordered action/token identity snapshot for the queue panel. Unchanged queues avoid repeated Lua traversal without relying on mutation hooks; snapshots belong to their panel and are released when it is hidden or removed.

### 0.1.64

- Ignore unnamed model scripts during cart transition and grounding rendering, preventing render-thread null-pointer exceptions while preserving processing of valid cart models later in the slot.

### 0.1.63

- Match steady forward cart walking, running and sprinting to native no-cart movement at the same effective carried weight and injury. Remove the extra held-cart container penalty while Toolkit controls the cart, preserve native gait eligibility, and retain cart acceleration, braking and cautious reverse behavior.

### 0.1.62

- Blend native injury clips into cart locomotion with matching movement budgets. Keep both wheelbarrow hands reachable through injured poses with bounded, model-specific upper-torso correction; preserve native hip/leg animation and outgoing gait fades.

### 0.1.61

- **Fixed:** Player pathfinding treats closed barricaded doors as obstacles and takes an available detour, preventing Distribute Loot from attempting the door and clearing its remaining queue. Ordinary doors, zombie destructive routes and reopening the route after barricade removal retain their native behavior.

### 0.1.60

- Fixed: A paid multiplayer action no longer resets the queue when its item change arrives before the native completion packet. An exact accepted transaction can wait for its confirmed result within the existing deadline; completion still requires native Done and the sealed server receipt. Local cancellation and stale/rejected transactions remain authoritative.

### 0.1.59

- Let enabled clocks and wristwatches catch a scheduled time crossed between updates, using their normal sound, wake-up and world-sound paths. Preserve daily repeats, explicit silencing, disabling and schedule edits; unchanged network setting packets no longer silence or restart a live ring. Initial load does not replay old alarms. Supports the B42.21 client and server; native sound-start events let Toolkit reset acceleration without adding UI.

### 0.1.58

- **Host startup:** Supply ZombieBuddy automatically to the native Host/soft-reset server process when the client is already patched. Normal Steam launches no longer require a separate Host launcher. Preserve saved approval policy, native server arguments and existing explicit/inherited loaders; diagnose duplicate loaders and unsupported native startup instead of changing system-wide JVM settings. Vehicle diagnostics remain controlled in-game.

### 0.1.57

- **Host vehicle inventory:** Include early item changes in each recipient's first native vehicle snapshot, then send later changes on the same ordered channel. Cover direct vehicle containers and bags directly inside them; preserve native transfers, recipient relevance and diagnostics, and reset synchronization across reconnects, world changes, vehicle deletion and ID reuse.

- **Compatibility:** Remove a proven orphan mesh-object animation channel from three DAMN Library clips before skeletal import. Preserve all skeletal frames and transforms; changed or unknown inputs keep native handling and diagnostics. No third-party assets are copied or rewritten.

### 0.1.56

- **Shopping carts:** Share a bounded walking phase across straight motion and turns, with smooth entry/release and a small planar stance correction that releases through the original swing. Preserve native foot roll and protect the knees without predicted landing targets, wide foot arcs or forced knee splay. Abrupt network yaw corrections retain native walking until root motion is stable; reverse and fast gaits retain their native clips.
- **Shopping carts:** Keep the handle stable through walking and turning, widen the supported grasp and relax the elbows without arching the back. Share the reachable held position with pickup/setdown and the physical rear-axle pivot.
- **Shopping carts:** Steer around the held model's fixed rear axle, including item scale, during forward/reverse travel and stationary turns. Keep the front casters free, match stationary steps to the handle arc and retain angular ramping across short movement budgets. Wheelbarrow handling and multiplayer packet fields/rate retain their existing behavior.

### 0.1.55

- **Vehicles:** Synchronize the rendered passenger position and both legs with Toolkit's entry/exit steps. Keep the support foot planted during weight transfer, lift the swinging foot and apply the same corrected pose to body and clothing. Normalize the chair animation's raised origin; logical seat ownership, collision, action completion and network messages stay native.

### 0.1.54

- **Fixed:** Hold an invalidated standard Host action whose exact native transaction is already Done while waiting, for up to 30 seconds, for its matching completion receipt. Suppress its stale update and let the original native callback finish once. Explicit stops, ownership changes, rejected/ambiguous transactions and expired waits cannot revive the action; successfully completed loop actions retain native behavior.

### 0.1.53

- Replace vehicle-trace time/record cutoffs with continuous UTF-8 file recording, rotating at 5 MiB with four backups per side. Preserve sampled cadence, reuse sampling slots over long sessions, and expose recoverable file errors without duplicating samples to console logs.

### 0.1.52

- Allow bounded vehicle-sync recording to be started and stopped at runtime. Keep the optional startup JVM flag, sampling limits and unchanged vehicle/network behavior; a completed recording can be explicitly restarted.

### 0.1.51

- **Action queue / Host completion:** Let the native engine finish an owned, server-completed action when its replicated target has already disappeared. Preserve its original completion cleanup and subsequent queued work without replaying server effects. Require the exact native transaction and sealed completion receipt; explicit stops, movement, combat, custom synchronization and disabled-queue behavior retain their existing paths.

### 0.1.50

- **Host radios:** Apply the native power-off update when a portable radio has returned from a hand to its owner's main inventory. Validate the connection, exact item and packet before using the native decoder and relay; held, world, vehicle and other state packets retain their existing paths.

### 0.1.47

- **Wooden cart clearance:** Adjusted the held wheelbarrow position to reduce contact with the player's legs and clothing while preserving the native gait and grip. Some clothing and character variants still need review.

### 0.1.46

- **Wooden cart equip:** Ground the held model and close its hand grip as soon as the native inventory action exposes the exact cart in both hands. Avoid the initial attachment jump while waiting for the next Lua motion refresh or remote motion pose; retain native action timing, locomotion, network steering gates and the existing outgoing-inventory clearance curve.

### 0.1.45

- **Wooden wheelbarrow:** Smoothed the transition into the held pose to reduce leg and clothing contact while preserving native leg motion, action timing and grip. Other character variants and Host still need review.

- **Changed:** Improved wheelbarrow clearance during fast movement and animation transitions while preserving the native cadence and grip.

### 0.1.44

- **Host transfers:** Include earlier items in an incoming ordinary container-transfer batch when native server validation accounts for reserved capacity. Reject the whole batch before any transfer when it cannot fit; keep fitting batches, native item rules and cancellation ownership. Floor and special transfer paths retain their native admission.

### 0.1.43

- **Fixed:** Preserve a closed fist and native thumb on metal wheelbarrows; correct the wrist angle and seating around the handle shafts instead of opening the fingers. Keep the accepted body/cart stance and the open-hand approach during pickup and setdown.

### 0.1.42

- **Changed:** Metal wheelbarrows sit closer to the body with lower handles, letting the arms hang nearly straight during idle and walking. Fast movement retains measured arm reach and leg clearance, with matching wheel steering and collision distances.

- **Fixed:** Cart pickup keeps the cart grounded and the hands on its handles while native equipment completion hands over to the ordinary held pose, including repeated native equipment snapshots received by the observer. The short visual handoff does not alter steering, inventory authority or network traffic.
- **Fixed:** Metal wheelbarrows retain both grips through native sprint-braking poses that previously exceeded the shoulder reach limit. A bounded model-specific clavicle adjustment preserves fixed arm lengths, the handle positions and native gait.

### 0.1.41

- Reset omitted numeric food-stat fields before decoding a reused native item-stat packet. Prevent one item's cooking time, nutrition and other food effects from leaking into the next item in multiplayer; preserve the native wire format, explicit values and poison-detection sentinel.

### 0.1.40

- **Changed:** Shopping carts animate four tires independently and smoothly turn their front caster supports from rendered travel, preserving wheel angles across pickup and setdown without additional network messages. Tire shapes are corrected for the imported nonuniform model scale; the established steering and grip remain unchanged.
- **Fixed:** Shopping-cart direct ground rendering compensates its native height offset and retains wheel orientation instead of using a cached atlas image.
- **Changed:** Shopping-cart ground transitions retain their imported nonuniform mesh basis and native world scale, with centered handle placement and a separate standing pose profile.
- **Fixed:** Shopping carts retain the same mesh size through ground/held transitions and rest on all four tires; the standing grip follows the native torso without scaling or tilting the body.
- **Changed:** During metal wheelbarrow pickup and setdown, the hands rotate smoothly around the shafts as the handles rise or fall, reducing the low wrist bend while preserving palm contact and the held grip.
- **Fixed:** Unheld metal wheelbarrows rest on the tire and both support feet. Pickup and put-down use the same corrected ground pose, and the character approaches farther between the handles. The held cart calibration is preserved. Small remaining facing turns finish before pickup; the metal clip acquires its grip once and keeps the cart within reach during immediate setdown retries.
- **Changed:** Metal wheelbarrow ground actions select their own authored body clip and use a matching grounded reach in the procedural path. Both clip variants retire their native tracks on cancellation and repeat without resetting outgoing fade clocks.
- **Fixed:** Metal wheelbarrow hands grip across the shafts and farther inside their ends, with model-specific palm depth and finger closure shared by pickup, held movement and setdown.
- **Changed:** Ported the wooden wheelbarrow gait, turning, braking, reverse and stationary pivot presentation to the metal model, with its measured handle positions, wheel size, axle and collision envelope. Both models share transition logic while retaining their own grip and elbow calibration.
- **Fixed:** Metal wheelbarrow grip remains reachable during braking by using bounded clavicle rotation without stretching the arms. Wheel rotation, floor contact and held/world handoffs use the matching model geometry.

### 0.1.39

- **Fixed:** Cancelling wooden-wheelbarrow setdown while running now returns the handles to the current movement pose, avoiding the jump from an idle endpoint. Moving pickup recovery preserves the knee's forward bend when a lifted toe changes direction.

### 0.1.38

- **Fixed:** The male character's right trouser leg no longer clips the wooden wheelbarrow handle during the checked single-player emergency wall-fall transition. A short, smoothly blended knee adjustment preserves the foot, pelvis, actor root, stationary cart and native backward recoil. Female poses and Host behavior are unchanged.

### 0.1.37

- **Fixed:** After a confirmed single-player wooden-cart emergency release, the character no longer steps forward through the stationary cart. The bounded impact episode preserves the stock backward recoil, lateral motion and obstacle collision, and clears on state or ownership changes.

### 0.1.36

- **Fixed:** Wooden-cart emergency release preserves the rendered axle position and eases the handles down over 240 ms. The exact-item transition survives the native floor-inventory projection, restores pooled renderer state and clears on pickup, expiry or world exit. This presentation fix applies to single-player; stock fall motion and its remaining body overlap are unchanged.

### 0.1.35

- **Fixed:** Remote wooden-wheelbarrow rendering validates a shared character/cart pose against nearby obstacles, with matching camera and model depth and a gradual correction release. Native movement, manual reverse and cart synchronization traffic are unchanged.

### 0.1.34

- **Fixed:** Tiny accepted coordinate changes no longer repeatedly release wooden-cart pushing effort at a blocked obstacle. Forward contact is checked independently from the exhausted root-motion budget; releasing input, reversing or clearing the obstacle releases the stance. Native movement/collision and manual reverse are preserved.
- **Changed:** Cart pose synchronization carries an effort flag in its existing packet fields and rate budget; remote catch-up retains its required locomotion before entering the planted pose.

### 0.1.33

- **Changed:** Calibrated cadence and outgoing-gait clearance for the wooden wheelbarrow's authored pivot clips. Exact cart-type selection is derived locally for owners and observers without adding network fields.

### 0.1.32

- **Fixed:** Wooden carts keep a consistent collision-constrained path while aligning with a wall. Established contact preserves tangential travel and accepts only the inward movement made safe by the planned turn, preventing alternating sidesteps without changing manual reverse or wall clearance. Contact steering follows the native animation movement budget, avoiding residual sidestep flicker when deferred motion and the current frame have different durations.

### 0.1.31

- **Fixed:** Wooden wheelbarrow steering no longer accumulates yaw from rounded world coordinates after releasing the keys. Manual wall exits keep the requested turn direction while collision checks limit travel and rotation. Forward wall sliding finishes aligning with the wall and releases guidance when steering away or releasing forward movement.

### 0.1.30

- Smooth the grip during wooden wheelbarrow pickup and setdown, preserving the thumb pose through the native transition into holding the handles.

### 0.1.29

- Center the wooden wheelbarrow pickup approach while preserving native collision and final handle alignment.

### 0.1.28

- Prevent the inventory-icon silhouette from flashing when highlighting a wooden wheelbarrow in 3D. Preserve the orange model highlight and native sprite outlines when 3D ground items are disabled.

### 0.1.27

- Keep the wooden wheelbarrow grip continuous during setdown when native multiplayer position lag requires a little more shoulder reach; preserve hand targets, bone lengths and world placement.

### 0.1.26

- Use heading-relative keyboard controls for shopping carts and both wheelbarrows: forward/reverse motion and continuous left/right steering, preserving native movement and collision handling.
- Reconstruct cart grounding, grip, banking, wheel rotation and wooden pickup/setdown presentation for remote players from small throttled state snapshots, with identity, native-action and lifecycle guards.

### 0.1.25

- **Changed:** Startup patches own their bytecode contracts and installation checks instead of keeping those details in the central dispatcher; patch guards and gameplay behavior are preserved. Refactored under this existing version label in `4fc28c8`.
- **Version:** The forge candidate was locally labeled 0.1.23 during live verification; 0.1.25 integrates it without replacing the concurrent medicine and TV releases below. The historical live run does not cover every subsequently merged upstream change.
- **Fixed:** Refresh a registered workstation's stale spatial entity ID before decoding its CraftBench reference on the server. Removing an earlier object from the same square could otherwise cause `loadComponent` to throw while accepting a crafting request, leaving the client at 100% progress. Recovery requires the exact already-resolved workstation and matching incoming ID; no recipe effects are forced or replayed.
- **Checks:** Reproduced the 100% Forge Simple Blade stall in a disposable Windows Host world with all 48 selected mods and Java Patches 0.1.22. The same fixture with 0.1.23 passed ordinary hand crafting, unchanged-forge crafting and crafting after a real earlier-object removal: one blade, one charcoal/iron debit, conserved tool IDs and idle native action/UI. Only the Java mod changed. Native decoder/medical regressions also passed. Both live runs retain seven client font-loading errors; the fixed run has no server action errors but remains runtime `needs-review`, not a clean whole-pack acceptance. No macOS, WAN or second-client coverage is claimed.

### 0.1.24

- **Fixed:** Resolve recognized TV & Radio ReInvented video paths from the active mod directory on macOS, preserving native cache keys, dimensions and synchronous/asynchronous loading.

### 0.1.23

- **Added:** A guarded, read-only Lua accessor for the native food-sickness treatment cooldown in single-player and on the multiplayer server.

### 0.1.22

- **Added:** Wooden-wheelbarrow footprints respect walls, doors and vehicle hulls while allowing wall sliding. Tight contact requires a manual reverse manoeuvre before turning out.
- **Fixed:** Preserved full native lateral strides and anchored grip during stationary turns, smoothed bank reversals and improved handle clearance during side steps.
- **Fixed:** Preserved wheel rotation and floor contact across pickup, setdown and cancellation; native wall-impact recovery releases the cart through SaucedCarts.
- **Note:** These cart changes are client-local; multiplayer visual reconstruction and the remaining body/clothing contacts are not declared complete.

### 0.1.19

- **Added:** Side input from rest turns the wooden wheelbarrow with native lateral steps around its front wheel, then resumes pushing. Run/Sprint wait until the pivot finishes; opposite input retains backward movement.
- **Changed:** Stationary turns use full native lateral strides; cargo changes their cadence, preserving turning speed without rapid idle-blended shuffling.
- **Fixed:** Releasing a stationary turn consumes no residual sideways movement as an unwanted forward step. Native collisions still determine accepted rotation.

Previously named **PZ Network Fix** through 0.1.1.

### 0.1.18

- **Added:** Guarded client cart movement, pose/grip, grounded wheel rendering and cargo-dependent pace for the selected carts and wheelbarrows.
- **Fixed:** Preserved native gait cadence during transitions, capped braking by release speed and retained cart contact while heavy-item stops settle.
- **Changed:** Consolidated the cart candidate with the existing animal, equipment and hutch fixes. Native collisions and server-authoritative item ownership remain unchanged.
### 0.1.15

- **Fixed:** Rejected a late server medical action whose BodyPart owner disconnected before argument decoding. Native Reject acknowledgement replaces the null-player exception; valid requests and existing queued actions remain native.
- **Fixed:** Ignored an in-flight body-damage UPDATE after its patient disappeared from the client, preventing the native null-player exception. Valid health updates and subscription control packets retain native behavior; exact B42.21 bytecode is required.

### 0.1.10

- **Fixed:** Reconciled occupied-vehicle physics authority with the validated server driver after the reproduced collision/entry/release race, preserving towing ownership and native packet authorization.
- **Added:** Bounded, opt-in vehicle diagnostics with `-Dpz.vehicle.trace=true`; the ownership repair itself needs no flag. Updated server/client setup and platform-specific collection instructions.
- **Changed:** Combined vehicle recovery with the native string-property, fluid-container, fence-validation and early font-page guards from main under a distinct version. The vehicle-recovery candidate in a controlled macOS Host with two connected clients passed post-repair travel, towing/detachment and driver/passenger handoffs; spontaneous user-save and real WAN-loss incidence remain unverified.

### 0.1.9

- **Fixed:** Deferred native fence validation until script loading completed and corrected early font-page resolution. The font guard uses a separate local bootstrap JAR with explicit early loader activation.

### 0.1.8

- **Fixed:** Normalized the two shipped fluid-container name tokens `Large Bucket` and `Fuel Pump` before native parsing, preserving validation for other names.

### 0.1.7

- **Fixed:** Preserved five shipped native string properties without startup enum lookup exceptions, keeping alias IDs, values and string storage.

### [0.1.6](https://github.com/AlexRedby/pz-survivor-toolkit/commit/761aea81f0c699c34b3a41709d49cecc662dda94)

- **Fixed:** Prevented the B42.21 hutch-unloading crash caused by empty animal slots, while preserving existing animals and the original hutch data in clients, single-player and servers.

### [0.1.5](https://github.com/AlexRedby/pz-survivor-toolkit/commit/c3ad1e0aabec486e34e41caa76449c8b125a48f6)

- **Fixed:** Prevented incomplete equipment acknowledgements from clearing a just-grabbed animal from the local player's hands when equipment packets arrive before the animal transfer.

### [0.1.4](https://github.com/AlexRedby/pz-survivor-toolkit/commit/bd6d1088d8fb9a81219b6e4c7b15cd1446757fae)

- **Fixed:** Removed stale or duplicate client trailer membership when an animal's server-reported location changes to the world, a hutch or an inventory, correcting ghost animals and occupied trailer capacity.

### [0.1.3](https://github.com/AlexRedby/pz-survivor-toolkit/commit/f7de4db558b526e0fe55e4e2457230016af33a2f)

- **Added:** Server build acknowledgements that let Toolkit safely interrupt and resume multiplayer construction after confirmed cancellation, without replaying completed builds.
- **Added:** Optional programmatic game-window recording through Lua or Java for isolated test profiles, producing silent H.264 MP4 through FFmpeg without automatic recording or a new game menu.

### [0.1.2](https://github.com/AlexRedby/pz-survivor-toolkit/commit/9edadea9de0f5464b36197bb207ca9827b15aec0)

- **Changed:** Renamed PZ Network Fix to Toolkit Java Patches, including the local Mod ID, JAR and Java package; existing installations must enable `PZToolkitJavaPatches` instead of `PZNetworkFix`.
- **Added:** A macOS Host launcher that loads ZombieBuddy in the client and separate Host server process, using the bundled Apple Silicon or Intel Java runtime and refusing duplicate loader arguments.

### [0.1.1](https://github.com/AlexRedby/pz-survivor-toolkit/commit/aa101d6090c6612e867775b001caca90e8577c9b) (PZ Network Fix)

- **Fixed:** Prevented server-authoritative cassette/VHS playback from stopping again after a quick Stop/Play sequence.
- **Changed:** Packaged the Java patch for both clients and servers instead of the client-only Java directory.
- **Added:** A Windows Host launcher that passes ZombieBuddy to the child server process and avoids adding a duplicate client loader.

### [0.1.0](https://github.com/AlexRedby/pz-survivor-toolkit/commit/b8423c527640019fd246e172e1a9914a003b8691) (PZ Network Fix)

- **Added:** Experimental B42.21 client patches for remote zombie speed decoding and vehicle interpolation recovery, with ZombieBuddy and per-class bytecode guards that disable unsupported patches.
- **Fixed:** Corrected standard Steam game-path defaults for Windows and Linux and added clear missing-JAR checks.
- **Fixed:** Required JDK 25 or newer to read B42.21 game dependencies while retaining Java 17 output compatibility.

## Development tools

- **macOS native tests:** Keep connected sleeping displays available through a sealed, fingerprint-checked private GLFW copy. Default automatic launch routes windows through AeroSpace or uses a transparent sleep-only fallback, then reveals them only after verified workspace recovery. Add explicit desktop-policy CLI flags, separate startup/discovery deadlines and a bounded wake-transition grace; diagnose sandbox GUI access without asking users to wake the display. Real GPU, SP and Host startup checks passed with the physical display asleep; vanilla runtime diagnostics remain visible in reports.

- **Cart action invalidation diagnostics:** Add a selected native world-identity loss/cancellation/retry bank with exact source and action binding, preserved cart/cargo, all-role endpoints and historical terminal replay refusal. Add a composed native signed-byte reuse regression through the production acknowledgement and Lua receiver; keep natural allocator wrap and production migration separate.

- **Initial inventory-entry diagnostics:** Add a separately selected real inventory Push Cart entry to the menu lifetime bank. Join sealed action receipts to canonical native completion, require all-role held endpoints before the first lifetime, and retain the later same-cart release/pickup fences. Repeated inventory return and production/visual qualification remain separate.

- **Cart public-input diagnostics:** Bind admission to the selected Drop/Setdown kind, keep completed Drop receipts separate from queue-reset revocation, regress delayed old receipts during a fresh Drop, and add an explicit owner world-menu release/pickup lifetime bank with all-role native absence and stale-message fences before and after rebinding. Keep native transport checks callback-scoped and use retained identities only to close old authority. Distinguish hard held/empty transitions from certified same-lease Equip resnapshots.

- **Cart capture sampling:** Preserve each real native motion tick instead of discarding observations under the 100ms state throttle. Keep slower post-motion state logging, independent action sampling and unchanged analyzer coverage limits.
