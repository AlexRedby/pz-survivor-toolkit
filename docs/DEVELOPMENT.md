# Development

[Overview](../README.md) · [Feature guide](FEATURES.md) · [Open work](../TODO.md)

Run commands below from the repository root.

## Versioning

Before pushing changes to main, compare each changed component with the latest main. Changes to shipped code, assets or runtime metadata, including behavior-preserving refactors, require a version newer than main for that component: Toolkit uses [mod.info](../PZSurvivorToolkit/42/mod.info); Java Patches uses the generated metadata in [build.py](../JavaPatches/build.py). One bump can cover the complete set of changes delivered together; individual implementation commits do not each need a bump. Record the delivered changes in [CHANGELOG.md](../CHANGELOG.md) and recheck versions after merging concurrent work. Changes confined to tests, development tools, documentation or agent instructions do not require a mod version bump.

## Verification environment

Agent verification on macOS is sufficient for this project's Windows/macOS gameplay targets. Do not pursue Windows test environments or make Windows verification a routine completion requirement; Windows players check the project there. State the platform actually tested and do not present a macOS check as Windows verification. A separate dedicated-server run is not a required verification target.

Use the [native runner guide](../tests/native_queue/README.md#commands) for isolated settings/saves and macOS window placement, including AeroSpace and current-desktop fallback.

## Cart animation authoring in Blender

Start from a clone of this repository and install these external prerequisites:

- Python 3.10+ for the launcher; no pip packages are needed for this workflow.
- Blender 4.5 LTS, including its bundled Python, `bpy` and `mathutils`.
- JDK 25+ with both `java` and `javac` for the native export check.
- The supported Project Zomboid B42.21 installation. Its Java directory must contain `projectzomboid.jar`, the native importer libraries, `media/anims_X/Bob/Bob_Idle.x` and `media/models_X/Skinned/{MaleBody,FemaleBody}.x`.
- For the wooden pickup's cart reference, the installed Steam Workshop item **3689975894**, SaucedWheelbarrow. The required file is `mods/SaucedWheelbarrow/42/media/models_X/weapons/2handed/Wheelbarrow_wood.fbx` inside that item's directory. An existing local copy can be selected with `--cart-fbx`.

All project scripts, native check helpers, presets and editable pose sources are in Git under `tools/`, `tests/` and `assets/animations/`. Blender, the JDK, game files and Workshop models are external installations. The `.blend` scene is generated from those inputs; no pre-existing scene, Codex installation, account configuration or agent investigation files are required.

On macOS the launcher discovers Blender in `~/Applications` or `/Applications`, the standard Steam game path and the installed JDK. From the clone's root, run:

```sh
python3 tools/cart_blender.py prepare --clip wood_cart_pickup
python3 tools/cart_blender.py edit build/blender/wood_cart_pickup
python3 tools/cart_blender.py export build/blender/wood_cart_pickup
python3 tools/cart_blender.py render build/blender/wood_cart_pickup --frame 20
```

For nonstandard installations, pass paths when preparing the workspace:

```sh
python3 tools/cart_blender.py prepare --clip wood_cart_pickup \
  --blender /path/to/Blender.app --jdk /path/to/jdk-25 \
  --game /path/to/game-Java \
  --cart-fbx /path/to/Wheelbarrow_wood.fbx
```

`--blender` also accepts the Blender executable directly. `--workshop /path/to/steamapps/workshop/content/108600` selects a different Steam library instead of a single FBX. Windows users can use `py -3` in place of `python3` and pass their installed executable/JDK/game paths; verification here was performed on macOS.

Preparation creates `build/blender/wood_cart_pickup` containing `scene.blend`, its configuration and macOS double-click launchers. It never replaces an existing workspace; use `--output` for another version. The wooden pickup preset includes the measured playback duration and a calibrated cart reference. The other supplied source clips are `metal_cart_pickup`, `shopping_cart_pickup`, `wood_cart_brace`, `wood_cart_pivot_left` and `wood_cart_pivot_right`; use `--clip NAME --duration SECONDS` with their actual playback duration. These have a live body without a cart reference. Add `--female` to prepare the native female body.

The body follows pose edits immediately through saved Blender constraints and linear skinning; reopening the scene does not require script auto-run. The editable `CartClip` skeleton is separate from the hidden bind skeleton. The prepared viewport starts in Pose Mode with Auto Key enabled. Space plays the clip; the Dope Sheet edits key timing. Open through the launcher to load the **PZ Cart** sidebar and its **Save + Export to PZ** button. A direct double-click on `.blend` retains the live mesh but does not register the session-only sidebar.

Exports retain added and moved keys and create a new `exports/` snapshot with pose JSON, native `.x`, logs and `report.json`. Native PZ import/FK must reproduce the scene's keys and intermediate frames within the matrix tolerance before the result is reported as passing. Bezier curves or authoring constraints require the sidebar's bake option or `export --bake-fps 60`; the exporter increases sampling up to 240 fps when the native checker detects an approximation error, and fails if that still exceeds the tolerance. The low-level `cart_clip_blender.py export` still defaults to original timestamps; the workspace launcher uses authored key timing.

`build/blender/` contains generated scenes, local absolute paths, imported game/Workshop geometry and export snapshots. It is ignored by Git and excluded from mod packaging. A new clone recreates it with `prepare`; after moving the clone or changing machines, prepare a new workspace rather than copying the old configuration. Preserve any hand-edited scene separately before removing an old workspace. Export does not replace repository animation sources or install anything into the game. The cart is an authoring reference: runtime hand IK, ground adaptation, clothing, interruptions and multiplayer transitions still require PZ checks. Offline verification was performed on macOS with Blender 4.5.9.

Run the fast parser/bridge checks with `python3 -m unittest discover -s tests -p 'test_cart*blender*.py'`. To exercise actual edits, key insertion/retiming, reload and the sidebar's native export, run Blender with `--background --python-exit-code 1 --python tests/blender_cart_edit_check.py -- WORKSPACE`; this creates a separate `verification/` scene and leaves the original scene unchanged.

### Replay an inventory-equip transition

Inventory-menu equip uses the native inventory animation, not the ground-pickup clip. To inspect its outgoing blend, capture the SP `wooden_cart_motion/approach` scenario with `cart_entry_contact_repro: true` and explicit `cart_scenes: ["container-equip"]` (or include `"wrong-side"` for a separate ground-approach control). The option records native Walk before the actual inventory callback, worn male baggy jeans, full cargo, full influencing bone palettes and a one-second held tail. Use the native runner's explicit dependency paths and isolated settings; source snapshots and geometry reports do not establish every rendered frame.

The replay and curve-authoring tools run inside Blender. `BLENDER` below means its installed executable; `GAME` is the folder containing `projectzomboid.jar`, and `CART_FBX` is the installed wooden-wheelbarrow model. Replace `PROFILE` and `LOG` with the captured client profile and its `console.txt`:

```sh
"$BLENDER" --background --python-exit-code 1 --python tools/cart_blender_replay.py -- \
  --profile "$PROFILE" --log "$LOG" --game "$GAME" --cart-fbx "$CART_FBX" \
  --output build/blender/inventory-replay
"$BLENDER" --background --python-exit-code 1 --python tools/cart_blender_clearance.py -- \
  prepare build/blender/inventory-replay/replay.blend build/blender/inventory-clearance
"$BLENDER" build/blender/inventory-clearance/authored.blend
```

The replay verifies Blender's evaluated body and actual `Bob_Trousers` mesh against every captured native sample within `2e-5` model units. Unweighted Nub bones are filled from their parents; all 35 influencing native bones remain measured. The saved scene works without script auto-run. Select **Equip clearance envelope** and edit its Y location curve in the Graph Editor. Frames 1..61 represent the retired share of the outgoing inventory animation, rather than scene time. A saved Action constraint evaluates the curve against recorded blend weights, so edits update the cart preview immediately. The preview arms remain recorded; actual runtime IK and closed grip require the game check.

```sh
"$BLENDER" --background --python-exit-code 1 --python tools/cart_blender_clearance.py -- \
  export build/blender/inventory-clearance/authored.blend build/blender/inventory-clearance/export
```

Export creates a new curve JSON, generated Java sampler and approximation report. It checks zero endpoints, forward-only bounds and intermediate samples, increasing sampling until the interpolation error is below `2e-6` model units. To propose a runtime change, review both outputs and update `assets/animations/curves/wood_cart_equip_clearance.json` and `JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartEquipClearanceCurve.java` together. `tests/test_cart_clearance_curve.py` checks that they agree. Build and test the candidate through the isolated reproducer; exporting or opening the scene does not install or validate gameplay. The current envelope is a rendered cart-placement correction while inventory Loot retires; it does not replace the pickup clip or native legs.

### Recalibrating the held-leg clearance cage

The held wooden-cart fit reads the native render slot's body and supported trousers palettes. Its generated source cage and shaft decomposition are committed in `CartLegClearanceData.java`; ordinary Java builds need neither Blender nor NumPy. A changed game/Workshop asset hash disables that asset's calibration until it is reviewed and regenerated.

Regeneration requires Python with NumPy, the supported B42.21 game files and the original wooden cart FBX:

```sh
python3 tools/cart_leg_clearance_profile.py --game "$GAME" --mesh "$CART_FBX" \
  --output JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartLegClearanceData.java
python3 tools/cart_leg_clearance_profile.py --game "$GAME" --mesh "$CART_FBX" \
  --output JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartLegClearanceData.java --check
```

The generator verifies source identities, skin weights and exact kernel-fan decomposition of the nonconvex closed shaft pieces. Open braces retain their original triangles. The runtime selects the nearest lateral corridor with a 1 mm source-cage margin, rechecks the solved hand pose and refuses a nonzero correction whose calibrated cart vertices leave the existing Walk footprint. Native collision, leg/root motion, packet frequency and the Blender forward envelope remain unchanged. Source-cage regressions and captured matrices do not certify unseen clothing or every GPU-rendered frame; rerun the isolated SP/Host checks after recalibration.

## Checks and packaging

Behavioural checks run with Lua 5.1 through Lupa. They use world/UI doubles; they are not visual in-game tests. Choose checks related to the change; the commands below are independent examples, not a mandatory full checklist.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install lupa
.venv/bin/python tools/run_tests.py --test test_tv_controls
python3 tools/package_mod.py --check
python3 tools/package_mod.py --output dist/PZSurvivorToolkit.zip
python3 -m unittest discover -s tests -p 'test_prepare_install.py'
python3 -m unittest discover -s JavaPatches/tests
python3 tools/prepare_install.py --check
```

List Lua tests with `.venv/bin/python tools/run_tests.py --list`. Select one or several with repeatable `--test NAME` (relative to `tests/`, with or without `.lua`). For example, `--test test_tv_controls --test test_vhs_ownership` runs only those tests and their associated variants, without scanning all mod files. Omit `--test` for the existing full Lua checks, including the syntax scan. Quartermaster checks always use the owned `PZSurvivorToolkit/42/media/lua` sources. Explicitly selecting its craft UI or the native tag transfer/placement checks also requires native game sources through `--game` or `--native-action-root`. Other checks retain their existing source-dependent SKIP behavior; a skipped integration check does not validate that integration.

Add `--game "$PZ_GAME"` (the directory containing `projectzomboid.jar`) to supply native Lua inputs from one installation. For example, `.venv/bin/python tools/run_tests.py --game "$PZ_GAME" --test test_inventory_tags --test test_vehicle_ground` reads the selected tests' native inventory and vehicle sources. This also supplies Mod Options, radio, action and Wishlist paths when their checks are selected. Individual source-path options override these defaults; locked integration checks retain their source-consistency requirements. Only selected tests read their inputs, and a missing required file fails instead of silently skipping it. Third-party source paths remain explicit or come from `--pack-lock`.

VHS menu, sorting, drop validation and live toggle checks run by default; add `--tv-source /path/to/RWMMergedTV.lua --game "$PZ_GAME"` to also exercise the upstream window and native media actions and drag parser.

The TV video source check runs the upstream catalog and original initialization without a separate video list. `python3 JavaPatches/build.py --test TVVideoPathChecks` checks the macOS path correction before native cache lookup, including failed-cache precedence and close/eviction keys; it does not decode video or prove GPU playback.

Independent medicine checks can use the installed framework with `--medicine-framework-source /path/to/MF_ISMoodle.lua`.

Warehouse checks are selected with `--test test_manifest_authority --test test_manifest_client --test test_manifest_view --test test_manifest_presentation`. `python3 JavaPatches/build.py --test ManifestModelChecks` executes the same text-boundary vectors against native Kahlua's UTF-16 strings. Use the native `warehouse-manifest/snapshot` suite for the SP/Host/UI boundary; its declared scope and screenshots are described in the [runner guide](../tests/native_queue/README.md).

The read-only Java global `toolkitMedicineCooldown(character)` returns the native food-sickness treatment cooldown, or `nil` for unsupported bytecode, unavailable data or multiplayer clients. `MedicineEffects.capture` sends this as `LemonGrassCooldown` (`false` when unavailable); the old `LemonGrass` estimate is never displayed as exact. Use `python3 JavaPatches/build.py --test MedicineCooldownChecks` for native field, loader exposure and Kahlua checks.

`--mpff-source /path/to/MPFastForward/media/lua` and `--bc-filter-source /path/to/CategoryFilters.lua` exercise the upstream modules and early compatibility gates; without these paths, those source checks report SKIP.

With `--game`, vehicle ground-placement regressions exercise the installed game's removal completion and item collection, including failure, callbacks and its existing ground fallback. Quantity-transfer checks use the actual inventory callbacks and sibling text-box constructor/callback; run `.venv/bin/python tools/run_tests.py --game "$PZ_GAME" --oc-stick-source "$OC_STICK_SOURCE" --test test_quantity_transfers` with `OC_STICK_SOURCE` pointing to the installed `organizedCategories_itemStick.lua` to also check original selection intent through its live transfer wrapper.

Action queue and native Wishlist menu checks use `--game`. Add `--wishlist-workshop-root /path/to/steamapps/workshop/content/108600` for the Wishlist checks against installed adapters.

`python3 tools/package_mod.py --check` validates the Toolkit mod structure without creating an archive. To create a developer-only archive, run `python3 tools/package_mod.py --output dist/PZSurvivorToolkit.zip`; Wishlist Lua sources are included automatically. Use `tools/prepare_install.py` to prepare both local folders, including the Java mod; it creates no archive.

To run the same checks against your installed game's native Mod Options implementation:

```sh
.venv/bin/python tools/run_tests.py --game "$PZ_GAME" --test test_highlighter
```


## Native scenarios

Use the [native runner guide](../tests/native_queue/README.md) for preparation, exclusive GUI ownership, control comparisons, runtime verdicts and coverage. The [contribution index](../tests/native_queue/contributions/README.md) lists registered adapters and their scope. Registration does not establish a native pass; use each run report and coverage matrix.

For selected-mod compatibility, run the relevant native suite with `--mods selected`; isolated Lua tests do not load that set.

## Regression scenarios

Use the checks below for the affected behavior. A fixture's assertions describe its acceptance contract; old successful runs and their assertion counts do not verify changed code. Keep native action durations when testing timing and network races; shortened reading or instant actions do not establish that coverage. Multiplayer item/resource effects require authoritative server checks, not client queue completion alone.

| Behavior | Scenario and checks |
|---|---|
| Queue cancellation and shared resources | Cancel waiting and supported active operations; remove or replace their inputs; have two clients compete for the same item IDs. Check that completed effects are not replayed, unrelated reading continues, and items/resources are conserved. See [queue regressions](../tests/test_action_queue_operations.lua) and the [native runner](../tests/native_queue/README.md). |
| Medical disconnect | Run matching native/toolkit controls with `nativeStop,remoteRemoved`, reversing doctor/patient roles. Audit clinical receipts and full runtime logs separately; a functional pass must not hide a new packet exception. The commands are in the [native runner guide](../tests/native_queue/README.md#commands); unresolved causes remain in [TODO](../TODO.md#near-term-adapters). |
| Packaged food and bulk actions | Exercise missing inputs, shared selections, cancellation, late/duplicate receipts and partial portions. Verify the exact created food ID, once-only consumption, retained completed output and borrowed-tool returns. See [packaged-food](../tests/test_packaged_food.lua) and [bulk-food](../tests/test_bulk_food.lua) regressions. |
| Crafting plans | Repeat recipes with explicit material picks and Auto, compete for a shared log, cancel a waiting plan, and reopen/resize its UI. Check source/output IDs, tool returns and preview cleanup. Use the [crafting-plan fixture](../tests/native_queue/contributions/crafting-plans/README.md). |
| Wishlist | Test concurrent edits, explicit/faction access revocation, a clean server/client restart and catalog window cleanup. Use the [Wishlist fixture](../tests/native_queue/contributions/shared-wishlist/README.md). |
| Java animal fixes | Compare unpatched/patched early equipment delivery, replay a late trailer snapshot, and compare synchronization with the timer mod absent/present. Check exact animal identities, all native grabs/drops and direct periodic sends. Use the [animal-trailer fixture](../tests/native_queue/contributions/animal-trailer/README.md). |
| UI and recording | Exercise both inventory modes, scaling, expanded stacks and repeated window close/reopen; inspect screenshots. Use the [item-tag fixture](../tests/native_queue/contributions/item-tags/README.md) and [video fixture](../tests/native_queue/contributions/video-recording/README.md). Successful callback assertions alone do not establish physical input or correct rendering. |

## Crafting controls

`CraftingControls` owns the extra rows in `ISCraftRecipePanel` and the footer in `NC_CellBaseCraft`. `CraftChains` and Wishlist register their buttons with explicit order, enabled/visible predicates and feature callbacks. The owner rebuilds native rows, reserves the combined footer height and updates visibility; consumers must not wrap those create/layout/prerender methods independently. An embedded plan receives the content height left above the visible footers. Project Cook and Building retain their specialized Wishlist adapters.

Keep recipe interpretation in its feature: Wishlist describes wanted items and approximate usable containers, the planner accepts exact executable recipes, and Quartermaster matches physical ingredients for hauling. Their quantities are not interchangeable.

## Action queue adapters

Queue regression checks use the installed game's Lua queue, base action, reading action and list geometry with simulated Java/UI lifecycle. Run them with `--game "$PZ_GAME"`; without it or an explicit `--native-action-root`, those native-source checks are skipped.

`python3 JavaPatches/build.py --game "$PZ_GAME" --jdk "$PZ_JDK" --test DrinkFluidCompletionChecks` runs the same drinking boundary vectors in the game's native Kahlua without launching a world. This checks engine table semantics alongside the fast Lua runner; use the fluid SP/Host scenarios for actual action execution and authoritative effects.

For development, `ActionQueueDefinitions.lua` owns presentation entries; changing an icon or title does not grant queue permissions. Family adapters register a separate behavior with explicit nonempty `types` and `matches`/`inspect`. The type list routes candidates; it never grants permissions without a successful matcher. Include deferred command and private wait types explicitly. Matcher errors or ambiguity reject the applicable type; unrelated families are not consulted. `ActionQueuePolicy.lua` returns read-only decisions with a reason, blocker and resource; it never calls action validity callbacks. Each decision owns a lazy context for contracts and operation items, including rejected contracts; never retain or reuse that context between decisions. Direct `Policy.inspect` calls remain fresh. Use `items` for directly used item IDs and `containerOwners` for bag references through `Policy.addContainerResources`; references conflict with bag changes, not with other references. Use `dynamicInputsByType` for native moduleless item selectors, alongside full-type `dynamicInputs` where applicable. Keep future selections and unknown effects explicit, and test both a shared and an independent target before allowing edits. `ActionQueueOperations.command`/`enqueue` reuse native deferred actions. Asynchronous adapters must capture `attachContinuation(token, character)` before waiting, then use `runContinuation(handle, callback, ...)` or `finishContinuation(handle)`; `runWith` intentionally remains available for required native cleanup after cancellation. `ActionQueueCompat.lua` contains source-pinned mod adapters and native completion boundaries. Health private-handler support is pinned to the reviewed B42.21 source and remains closed when that source or its hooks differ.

Run `.venv/bin/python tools/audit_action_queue.py --native-root /path/to/media/lua --workshop-root /path/to/content/108600 --selected-ini SurvivorQoL-selected.ini --require-native --output /tmp/action-queue.json` with the test dependency Lupa installed. The generated catalog distinguishes source presence, presentation and behavior declarations; it does not claim that fixtures or live scenarios passed. Run `python3 -m unittest discover -s tests -p test_audit_action_queue.py` for the scanner checks. The Lua runner also accepts `--project-cook-picker /path/to/PJCK_CookerPicker.lua` for that UI binding. No game installation gives an explicit skip; `--require-native` makes it a failed release gate.

`ActionQueueSettlement.finish` owns cancellation cleanup after the current native step and any required Host acknowledgement. It drops the remaining body, preserves registered cleanup and schedules exact-ID returns before the independent tail, without replaying effects or recreating items. Families register `retain(action, current, queue)` and optional `ownsPickup(current, id)` callbacks through `ActionQueueSettlement.register`; these callbacks keep their existing source/effect proofs and grant no additional edit permissions. A request records the body/cleanup/scheduled phases and cannot schedule twice. `scheduled` means cleanup was queued, not that its native effects succeeded. Mask and fitness restoration use this path. Delayed P4 restoration uses shared deferred ownership while retaining its source/intent proofs and native executor.

For delayed producers, `ActionQueueSettlement.deferred` captures the queue generation and `remember` snapshots task input/pickup claims. `owner` resolves only an exclusive exact-ID/type/destination return; unknown or conflicting claims keep a separate shared cleanup token. `context`, `isLive`, `obligation` and `required` bind cleanup to that ownership, while `close` retires aborted scopes. These historical claims are not authoritative effect receipts and never execute actions or reserve inventory. P4 retains ordinary native fallback with the queue disabled; already-running native completion is not suppressed by a late token cancellation.

For local debugging, call `PZSurvivorToolkit.ActionQueuePolicy.setDiagnostics(true)` in the Lua console, exercise a move/cancel/priority request, and inspect `getDiagnostics()` on the same object. It retains at most 64 decision records in memory, including adapter, item IDs/types, source and blocker; it sends nothing externally. `setDiagnostics(false)` clears and disables it. Pending family migrations and their completion gates are in [TODO.md](../TODO.md).

Kahlua omits the standard Lua `next` global; use `pairs` and model its absence in Lua 5.1 tests. It logs failed assertions even when `pcall` catches them and does not provide reliable weak-table cleanup. Unsupported inspection paths should return unknown/protected resources without throwing. Explicitly release completed operation records, listeners and closed UI owners; include repeated queue and window lifecycle checks when changing ownership.

## Inventory presentation

`InventoryPresentation` is the single Toolkit installation boundary for capacity icons/buttons, expanded item details, stack ordering and Wishlist row highlights. It installs once on each CleanUI/native inventory class, including classes created during a mode switch. The renderer supplies actual icon coordinates and texture dimensions; capacity indicators never reconstruct rows, replace drawing methods or adjust scroll offsets. Dirty redraw captures the physical Shift anchor before native code clears its old rows.

Wishlist's `Inventory.draw` runs once after normal detail rendering through this boundary. It uses the completed native rows for full-width highlights, including mixed stacks and items without a texture; icon calls are not a row-visibility contract. Wishlist retains matching, clipping and settings, but installs no pane or mode-switch hooks. Icon-grid and dragged-item passes do not receive row highlights.

`InventoryCapacity` draws bars and magazine segments. `InventoryDetails.draw` returns whether it handled the item; the boundary retains each class's native fallback. `InventoryDetailSort.refresh` owns bounded, lossless stack sorting after native refresh. It saves/restores selection only when a sortable prefix has at least two items; the Shift anchor still follows rebuilt rows when sorting does no work. Both detail modules read `InventoryDetailOptions`; the original Bravo/CCI Mod Options namespaces are retained only for persisted preferences, not runtime dependencies. Better Containers keeps its freshness renderer and settings; the presentation boundary tracks its public installer and gives item details the exact percentage column to avoid. Keep new display behavior in these presenters instead of adding another capture adapter.

`InventoryIndicators` lays out research, planting and Better Containers pin badges together at that same icon boundary, keeping simultaneous badges separate. The icon capture records whether the native/CleanUI row is a group header before the renderer proceeds to physical children; pin markers are header-only. Native rendering decides visibility and drag suppression. `InventoryResearch` delegates eligibility to the native recipe API for the pane's player; `InventoryPlanting` reads native crop definitions, actual recipe knowledge and live month/sandbox settings. Full packets are identified through `PlantingTags` and recipe metadata, so empty packets that teach the same season remain excluded. No seasonal category or sort override is installed. `InventoryPlantingOptions` retains the old preference namespace only.

`InventoryTooltip` owns scoped `DoTooltip` extensions for the exact active tooltip/item in both native measure/draw passes, preserving native placement, visibility and character selection. Providers register their data lookup and append function; nested calls, inherited item methods and failures must release the context and append each section once per pass. `InventoryPlantingTooltip` supplies the crop section. `InventoryMediaTooltip` reads the selected Show VHS Skills in Tooltip mod's public `SVSIT_logic` data, retaining its catalog, translations and name lookup. It sets the upstream `_vhsHooked` guard before `OnGameStart`: that callback still builds data but does not install its separate renderer. An already-installed upstream wrapper is reported rather than stacked.

For the selected Better Clothing Info provider, `InventoryClothingTooltip` delegates main content and wear comparison to BCI's public provider. `InventoryTooltip.renderBlocks` measures both blocks before placing their complete window using native context/mouse avoidance, controller origin or bottom anchor. It preserves BCI padding, backgrounds and options without copying its clothing calculations. A native-layout supplement reads the per-item/per-player `isNoRecipes` flag; BCI's copied header incorrectly queries the script type. Foreign Eury row providers and other owners retain their upstream compositor.

Check `test_inventory_tooltips` with `--game "$PZ_GAME" --vhs-tooltip-root /path/to/active/media/lua/client` or `test_clothing_tooltip` with `--game "$PZ_GAME" --bci-tooltip-root /path/to/active/media/lua/client` to reproduce upstream render defects and exercise the boundaries against actual game/mod sources. The [inventory tooltip fixture](../tests/native_queue/contributions/inventory-tooltips/README.md) checks real seed, VHS and clothing tooltips, the native NoRecipes flag and menu/anchor placement with the selected set, retaining screenshots for visual inspection.

Run `tools/run_tests.py --test test_inventory_presentation --test test_item_details` for focused checks. Research and planting checks are `--test test_inventory_research --test test_inventory_planting --test test_inventory_indicators`; add `--game "$PZ_GAME"` to exercise native farming definitions and tooltip rendering. The [inventory presentation fixture](../tests/native_queue/contributions/inventory-presentation/README.md) exercises native objects and both inventory modes without the external CCI, Item Details, HasResearch or SeedSeasonIndicator mods and produces screenshots for inspection.

## Inventory filtering and selection

`InventoryFilter` owns visibility by evaluating exact category, tag rules and `InventorySearch` together on each physical item, then projecting accepted items into native/CleanUI groups. CleanUI retains search controls and sorting; organizedCategories retains category overrides, stack splitting and pins. Do not use `group.cat` or `group.matchesSearch` as visibility authority: same-name stacks can contain different instance categories, and upstream search can satisfy name and category on different children. Search preserves literal name/display-name/type matching and canonical/localized display or base categories. Respect `cleanUIFirstActualIndex` for headerless groups, including rows rebuilt by organizedCategories without the optimization flag.

Each real refresh resets the full physical-item snapshot used for category/tag choices and the rule picker. Repeated selection restoration may adopt later split/pinned rows as its projection input, but must not replace that full snapshot with an already filtered view. `InventoryFilter.choices(pane, includeTags)` derives sorted category choices and the available tag set from those references on demand when opening a menu; pass `false` for category-only callers. Ordinary selection restoration only evaluates active visibility predicates. Re-read instance categories/tags from the snapshot's item references; do not cache their values. Filter selection sets its complete category/tag/rule state before one refresh. The same accepted physical-item set gates outgoing bulk transfers; destination filters must still accept incoming items. Run `tools/run_tests.py --test test_inventory_filter --test test_inventory_search --game "$PZ_GAME" --cleanui-inventory-pane /path/to/active/ISInventoryPane.lua --oc-display-source /path/to/organizedCategories_displayOverride.lua` for native refresh, upstream search and late split checks. The `pinned-items` selection case checks filtering alongside the real selected-pack row/selection pipeline.

`InventoryRows` owns the visible-row projection for saved selection and Shift anchors. `InventoryFilter` passes its effective, possibly remapped selection through the existing restore chain, then projects it onto the final details-view rows. Preserve whole-group versus physical-child markers, CleanUI group-name identity, hidden equipment and the rendered child limit. Keep filtering and sorting in their existing owners; do not add per-mod selection-offset repairs or rebuild selection from stale `pane.items` before rendering.

`000ToolkitBCPinsCompatibility` owns Better Containers pin ordering for both inventory classes and suppresses BC's sort/render installers. BC still owns pin state, menus, options and assets. Markers belong to `InventoryIndicators`; do not install another render wrapper, traverse the completed row cache or reconstruct icon coordinates from column width and row height. The `pinned-items` selection scenario checks actual icon bounds alongside selection, hidden equipment, capped stacks and drag suppression. The `inventory-presentation` fixture also checks scale changes and simultaneous badges.

## Item tag API

The shared `PZSurvivorToolkit/ItemTags` API exposes `forItem`, `forScriptItem`, `forCategory`, `label`, `matches` (all/any), bounded `normalizeRule`, `ruleActive`, `matchesRule` (all/any plus exclusions), and lossless `category` projection. Original IDs are retained to disambiguate aliases with identical tag sets; arbitrary tag combinations without a legacy equivalent return no category rather than inventing one. Unknown mod categories remain single opaque tags. Item reads follow the current instance category, including organizedCategories fluid changes. This layer does not modify native recipe `ItemTag`s, loot ScriptItems, item identities or existing category settings. Other mods continue receiving the original `getDisplayCategory()` value. Item/ScriptItem reads refine planting inputs from native farming props and full/empty packet metadata from `Base.OpenPacketOfSeeds`; category-only reads remain unchanged. Unmodified returned item-tag lists retain their exact legacy projection. These role tags do not replace native freshness, cooked/burnt or portion checks for planting. Quartermaster uses actual item tags at the public planner boundary, preserving native capacity, carrier and manual-selection behavior.

`PZSurvivorToolkit/ItemCategories` owns the optional inventory-category provider boundary. `forScript(script)` reads organizedCategories' public inventory category with a native category fallback; script tags and catalogs use it without changing the script's loot category. `prepareItem(item)` and `prepareContainer(container)` delegate fluid and instance overrides to that provider. Quartermaster calls preparation before sorting, reading picker contents and taking Manifest snapshots, so these operations do not depend on a prior inventory-pane refresh or external wrapper. `ItemTags.forItem` remains a read of the current instance category; do not replace instance-specific fluid, media or custom categories with a script/type lookup. Provider policy stays in organizedCategories; absence of the provider preserves native categories.

Audit known category IDs with `python3 tools/check_tag_categories.py --schema PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemTagSchema.lua --oc-root /path/to/organizedCategories_core --mod-root /path/to/selected-mod-sources --game /path/to/game-Java`. The checker compares exact IDs and reports unresolved dynamic writers. Run `python3 -m unittest discover -s tests -p test_tag_category_checker.py` for parser and CLI checks.

Use the [native tag checks](../tests/native_tags/README.md) for reconnect and cold-restart scenarios. Quartermaster's global preset-rule store has native single-player `seed` and separate-process `reload` coverage; see the [runner guidance](../tests/native_queue/README.md#files-and-contributions) for its cases and evidence requirements. The Host `quartermaster-distribution/sort` case also creates and edits a preset through the owned RPC/editor, then verifies linked-container sorting on the client and server. This coverage is distinct from local named filters. Automated callback and persistence checks do not establish physical mouse/controller input or WAN behavior.

`QuartermasterPresets` owns the preset/rule pair in every mode: `native()` and `rules()` read the published state; `transaction(fn)` supplies private drafts. SP commits them through the existing paired file storage. Host saves and publishes one revisioned `LootSorter_Presets` table containing both maps, importing matching-generation rules from the legacy sidecar once. `LootSorter_PresetSync` requests and replaces that complete client snapshot; old replies cannot roll it back. Open preset editors retain their whole draft and original revision until save/reopen. Container discovery is read-only; the Host container editor excludes unresolved preset links from its draft and persists that cleanup through ordinary Save. SP retains unresolved world links when its local library lacks the preset. `QuartermasterTagRuleAuthority` handles container authorization independently of preset persistence.

Container copy/paste and `LootSorter_Picker` Save use `LootSorter.snapshotDesignation` to detach selections, including numeric preset generations. The editor passes its complete draft through `QuartermasterTagRuleClient.saveBox`; `QuartermasterContainerConfig` applies categories, items, preset links, priority and optional appearance beside the tag rule after one authority/revision check, with one object transmission. Accepted replies mirror only submitted fields; closing an editor does not undo an accepted save. Copy/paste submits the same complete sorting snapshot without appearance, preserving the destination's name, icon and colour. The picker owns pending-save and late-reply guards, control construction, layout, row dispatch and controller navigation. `QuartermasterTags` supplies tag rows and rule editing through explicit calls; it does not replace methods on individual picker windows.

`ContainerAppearance` is the boundary to Better Containers' indexed per-user/global ModData. It reads without modifying live tables and writes through BC's storage helpers, updating the native custom-name keys without calling native `setCustomName` (which transmits the entire object). `ContainerAppearanceControls` edits a private draft; `ContainerIconPicker` reuses BC's cached icon catalogue. `ContainerConfigurationMenus` replaces only supported world-container rename/customize entries, across native and both CleanUI pages. Bags retain their original routes. Do not disable BC's customizer option to hide duplicate menus: it also controls appearance rendering.

Appearance suggestions consume the first positive selection event in the open editor, filling only empty fields from `ItemTags`/`TagVisuals`. Exact items use the same full type as their picker-row icon and do not suggest a name. Tag-rule Apply carries the first newly included tag separately from the normalized rule, whose arrays are sorted; saved categories/presets cannot recover past click order. Reset clears the draft latch. No automatic/manual modes or designation-derived copies are persisted. `ContainerTagIcons` resolves the owned `pzst-tag` icon kind through `TagVisuals` in BC's texture helper, including saved containers rendered without opening the editor and with tag UI disabled; other kinds retain BC behavior.

`QuartermasterCraftContainers` bounds storage availability to a crafting refresh for one player. `LootSorter_CraftMenu` scopes native `ISHandCraftPanel.updateContainers`, Neat `NC_HandCraftPanel.updateContainers`/`update`, and `NC_CraftLogicPanel.updateContainers` while preserving their original implementations. Neat's `update` has its own direct container read. Context is restored after nested calls and errors; window rendering grants no access. The fetch engine uses `inventory(player)` and suppresses storage throughout fallback input resolution. Keep these ordinary reads separate from recipe browsing so distant ingredients cannot be consumed before the physical haul. The queue compatibility proof accepts the installed getter only while it forwards unchanged, with the scope-query identity preserved.

`LootSorter.planTrips` in `LootSorter_Plan.lua` keeps designation matching separate from destination admission. Its optional seventh callback receives the original box/item records after the planned-capacity check. `LootSorter_Core` supplies native `isInside`/`hasRoomFor` reads (the latter includes `isItemAllowed`); rejected destinations do not reserve space, and selection continues in the existing preference order. Reachability belongs to the walk and execution-time transfer check.

Before assigning destinations, the planner captures each item's eligible carriers using initial free space and the read-only `accepts(carrierRef, itemRef)` callback. Trip batching reuses those carrier indices in their original preference order while tracking remaining space and effective weight per trip. An item with no eligible carrier is a `carry` leftover and never reserves destination space.

`SmartDeposit` owns the separate content-based routing policy for Better Containers' virtual proximity targets. Its single `plan` returns destination groups and per-item acceptance for both execution and drag feedback. Each dragged-items instance keeps an advisory allocation for at most 200 ms, invalidated by selection/target changes, pane refreshes, container events and UI-mode changes. Rendering reapplies that result; pane/page drop admission and execution always build fresh plans. Dirty flags, item counts and BC refresh epochs are not treated as complete stock revisions. It sorts a private selection, accounts for reserved capacity across the batch, and retains type/category/fallback precedence, BC corpse/locked-storage rules and OC Stick intent. The compatibility entry point replaces only BC's Smart Deposit installer at the original proximity installation boundary; both inventory modes use the same planner. Actual transfers use the native factory and retain its live validation. Check the focused `test_smart_deposit` and the [native partial-drop scenario](../tests/native_queue/contributions/smart-deposit/README.md).

`InventoryTransferProtection` reads organizedCategories' public enabled/state functions at use time. Quartermaster uses this boundary for automatic distribution; Quantity Transfers captures its deliberate single-row/stack exception from the original UI selection before flattening, eligibility filtering or limiting, and checks live protection again on confirmation. Display pins remain sorting state. Craft ingredient/tool pulls keep their specific-action behavior.

The craft-fetch engine uses one physical-item partition for quantity limits and fetch planning: ordinary native crafting sources first, then unseen designated-storage items in box order. Deduplicate by item object identity, not type/name/ID, because these source views may overlap. Ordinary availability and the remote-favorite exclusion retain their separate policies. Availability injection also avoids appending containers already returned by the live getter. When a haul relies on ordinary world ingredients, handcraft returns to its starting square to restore their reach; carried-only inputs need no such return. Surface recipes keep their existing workbench return.

For basic storage gameplay, the native `quartermaster-distribution` and `quartermaster-crafting` suites exercise real walking/transfers and crafting through the owned UI handlers, with exact inventory effects and Host authority. The distribution `backpack` case also checks that a higher-priority, native-restricted matching container is skipped in favour of an admissible destination. The crafting suite checks a kept-tool recipe through ordinary and Neat crafting; its standalone `uses` case checks full, carried and partial drainable supplies with exact remaining-use receipts. See the [runner guidance](../tests/native_queue/README.md) for scope and commands; a transfer-only Manifest check does not establish that either complete gameplay cycle works.

## Wishlist storage

See [server setup](../MOD_INSTALL.md#server) for storage location and backup/restore requirements. Files use two alternating checked copies; global ModData is deliberately avoided because vanilla clients can request named global tables without wishlist access. Single-player uses the same validation and storage. No item, recipe or loot content is modified.

Multiplayer refresh checks live access every five seconds, even with the window closed: inventory/world highlighting also consumes these lists. Model projects visible list revisions and effective faction metadata without reading entries. Service compares that projection together with recipient, error and loaded-context identity before building a detached snapshot; Server retains only the publication stamp and prunes offline players. Successful edits increment the list revision and immediately refresh other recipients. Faction departure can change access or displayed sharing without a list edit, so neither list revisions alone nor window visibility can replace the live access check. Failed storage reads remain retryable.

## Java development

Java Patches supports mixed Java/Kotlin sources. Use the [Kotlin 2.3.0 compiler distribution](https://github.com/JetBrains/kotlin/releases/tag/v2.3.0), selected by `--kotlin-home /path/to/kotlinc`, `KOTLIN_HOME` or `kotlinc` on `PATH`. Both `JavaPatches/build.py` and `tools/prepare_install.py` accept this option. The local compiler and stdlib versions must match 2.3.0; builds do not download dependencies. Kotlin compiles against the Java sources before `javac` compiles the Java patch wrappers, with both producing Java 17 bytecode against the installed B42.21 game. The ordinary JAR bundles the Kotlin stdlib under `net.alexredby.pztoolkitruntime.kotlin`, plus module metadata and license notices. A build-only ASM tool from the compiler distribution relocates application/runtime references, keeping the game's bundled Kotlin 1.4.10 separate. No compiler or relocation tool is shipped. The early font JAR remains Java-only; players need no Kotlin installation. The pilot does not include `kotlin-reflect` or promise Kotlin reflection over relocated metadata.

`TVVideoPaths.kt` is the first migrated helper. Its static JVM facade preserves Java callers, nullable filenames and the existing native path/cache guards. `Main.TVVideoPath` remains a Java wrapper because its writable advice parameter cannot be reassigned in Kotlin. Keep writable advice and early bootstrap in Java during this pilot. `--test TVVideoPathChecks` exercises the real woven game method; `--test KotlinRuntimeChecks` starts without the mod on the classpath, registers the built JAR through instrumentation and checks its private runtime alongside the unchanged game runtime. `--test FontColdChecks` checks the separate early font path.

`python3 JavaPatches/build.py` produces `JavaPatches/build/PZToolkitJavaPatches`; it accepts `--game` for the directory containing both game/loader JARs, `--jdk` for JDK 25+, and `--check` for native JVM regressions. The checks compare original and patched engine vehicle interpolation, vehicle ownership recovery (native collision race, validated driver/towing guards and idempotency), bounded opt-in vehicle tracing, media restart, build cancellation/completion behavior, animal location/identity/capacity reconciliation, equipment acknowledgements, hutch unloading and native string-property startup fallback (cold loader entry, IDs, values, storage and unrelated diagnostics), plus native fluid-container token normalization, fence-validation timing and early font-page loading; cart checks cover movement budgets/collision, native cadence and stop/reverse transitions, grip/grounding and wheel rolling. There is no separate zombie-speed regression in this command. Generated output is ignored by Git.

For one Java regression, use `python3 JavaPatches/build.py --test MediaChecks`; repeat `--test` to select more. When present, `--test` overrides the `--check`/`--check-video` groups; without it, those flags retain their existing behavior. `--help` lists the available test names. Each Java regression has a 120-second timeout; change it with a positive integer `--test-timeout SECONDS`. A timed-out test fails and retains its output in the reported `JavaPatches/build/<check-name>.log`. The limit applies to each test invocation, not to compilation.

Migrate associated regression bodies to Kotlin with each runtime module. The builder selects either `.kt` or `.java`, resolves selected Kotlin helpers, and compiles Kotlin checks against the original application metadata with friend access for `internal` declarations. It relocates the resulting test bytecode before compiling remaining Java fixtures; executed tests use the distributed private runtime. Java fixtures remain appropriate for a demonstrated loader or instrumentation contract: `KotlinRuntimeChecks.java` must start without any Kotlin runtime reference before it appends the mod JAR. Do not add the compiler, unshaded stdlib or raw application classes to its runtime classpath.

## Java patch boundaries

### Equipment acknowledgements

Version 0.1.5 fixes the reproduced empty-hands symptom. Equip uses ordered channel 0 while AnimalCommand uses channel 1. If Equip arrives before RemoveAndGrab, its local inventory lookup fails and parsing returns before consuming the remaining hand status. The client previously acknowledged its empty/old hands, the server accepted that acknowledgement and sent an equipment update that removed the animal from the client's hands again. The exact animal item remained in both inventories.

The client now omits acknowledgements for incomplete local equipment parses. B42.21 gives each handler an exactly bounded packet buffer; both that framing and EquipPacket have bytecode guards. Fully parsed packets, remote players, server handling and intentional equipment changes retain vanilla behavior. The patch does not create items, change IDs or reorder network channels. An unresolved secondary-only item after a fully read packet is outside this fix; the demonstrated animal carry failure occurs on the primary item.

### Hutch unloading

The fingerprint-guarded hutch-unload hook temporarily supplies a non-null snapshot of the native `animalInside` map to `IsoHutch.removeFromWorld`, then restores the exact original map in a finally-style exit, including on exceptions. Native superclass cleanup, hutch-manager removal and every present animal's cleanup still run. Empty slots, stored counts, animal references and map identity remain unchanged after the call. It creates/deletes no animals, edits no saves and does not suppress unrelated exceptions. Valid-only maps use the original path without copying; custom map implementations and unsupported game bytecode retain native behavior.

## Test video

Install [Toolkit Java Patches](../JavaPatches/README.md) in the isolated test profile and pass its own `-cachedir`, with `-novoip` and `voiceEnable=false`. No menu or automatic recording is added. ZombieBuddy exports these globals to client Lua:

```lua
assert(toolkitVideoStart("/absolute/path/to/test-profile/videos", "/absolute/path/to/ffmpeg"))
-- Run the animation or test segment.
assert(toolkitVideoStop())
-- Poll on subsequent ticks; stop returns immediately while FFmpeg finalizes MP4.
local video = toolkitVideoStatus()
if video.state == "completed" then print(video.file, video.frames, video.seconds) end
if video.state == "failed" then error(video.error .. " | " .. video.log) end
```

Use an absolute output subdirectory inside the current profile's cache directory; symlink escapes are rejected. Each capture gets a unique filename and a sibling `.ffmpeg.log`; existing files are never overwritten. Pass an absolute executable path to an installed FFmpeg with `libx264`. Java tests may call the same static `VideoRecording.start(directory, ffmpeg)`, `stop()` and `status()` methods in `net.alexredby.pztoolkitjavapatches`.

`start()` returns whether the request was accepted, not encoder readiness. A second start during `starting`, `recording` or `stopping` returns false without replacing the active session. `stop()` accepts only the first stop request. Status states are `idle`, `starting`, `recording`, `stopping`, `completed`, `failed`; fields include `file`, `log`, `error`, `width`, `height`, `fps`, `frames`, `captured`, `dropped`, and `seconds` (encoded duration). Inspect `completed` before reading the finalized file or starting another capture.

The fixed profile is silent H.264 MP4, 30 FPS, CRF 18, `veryfast`, yuv420p. It captures the displayed game framebuffer including UI, without desktop windows. Actual GLFW framebuffer dimensions are used (including Retina), up to 4K / 8,294,400 pixels and 4096 pixels on either axis. Odd dimensions are padded by one pixel for H.264. Resize ends the capture with `failed` and finalizes already captured frames. A minimized window can supply no new images.

Capture uses one direct RGBA buffer plus three bounded heap buffers (at most about 127 MiB at 4K). GL readback and one copy happen on the render thread; encoding and pipe writes happen on a separate daemon thread. Slow rendering or encoding holds the previous image over missing frame slots, preserving wall time to within one 30 FPS frame, rather than speeding up the clip. The final frame is held until the stop timestamp. `dropped` counts capture opportunities skipped because no buffer was free; it does not count every duplicated output frame. This is test instrumentation, and synchronous GL readback can reduce game FPS.

After stop, a 15-second watchdog aborts an encoder that cannot finish. Normal JVM exit attempts a four-second flush; force-kill, encoder failure or a full disk can leave an incomplete MP4. There is no audio input, codec implementation or permanent recorder. The Display hook retains the per-class B42.21 fingerprint guard.

Run `python3 JavaPatches/build.py --check-video` with `PZ_TEST_FFMPEG` set to the FFmpeg executable (otherwise found on `PATH`; sibling `ffprobe` is required). This checks timing boundaries, delayed/gapped captures, last-frame hold, decoded colors, exact duration/dimensions, stop without frames and encoder failure. Ordinary `--check` retains its existing engine regressions.

The native capture fixture currently covers macOS, English UI and single-player. Russian UI, multiplayer, Windows/Linux, live resize, sustained 4K and forced-shutdown recovery remain unverified. See the [video fixture guide](../tests/native_queue/contributions/video-recording/README.md) for preparation, recording and decoding commands.
