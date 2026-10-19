# Development

[Overview](../README.md) · [Feature guide](FEATURES.md) · [Open work](../TODO.md)

Run commands below from the repository root.

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

The CCI regression can also run against the installed third-party source with `--cci-source /path/to/ContainerCapacityIndicator.lua`. VHS menu, sorting, drop validation and live toggle checks run by default; add `--tv-source /path/to/RWMMergedTV.lua --game "$PZ_GAME"` to also exercise the upstream window and native media actions and drag parser.

The TV video source check runs the upstream catalog and original initialization without a separate video list. `python3 JavaPatches/build.py --test TVVideoPathChecks` checks the macOS path correction before native cache lookup, including failed-cache precedence and close/eviction keys; it does not decode video or prove GPU playback.

Independent medicine checks can use the installed framework with `--medicine-framework-source /path/to/MF_ISMoodle.lua`.

The read-only Java global `toolkitMedicineCooldown(character)` returns the native food-sickness treatment cooldown, or `nil` for unsupported bytecode, unavailable data or multiplayer clients. `MedicineEffects.capture` sends this as `LemonGrassCooldown` (`false` when unavailable); the old `LemonGrass` estimate is never displayed as exact. Use `python3 JavaPatches/build.py --test MedicineCooldownChecks` for native field, loader exposure and Kahlua checks.

`--mpff-source /path/to/MPFastForward/media/lua` and `--bc-filter-source /path/to/CategoryFilters.lua` exercise the upstream modules and early compatibility gates; without these paths, those source checks report SKIP.

With `--game`, vehicle ground-placement regressions exercise the installed game's removal completion and item collection, including failure, callbacks and its existing ground fallback. Quantity-transfer checks use the actual inventory callbacks and sibling text-box constructor/callback.

Action queue and native Wishlist menu checks use `--game`. Add `--wishlist-workshop-root /path/to/steamapps/workshop/content/108600` for the Wishlist checks against installed adapters.

`python3 tools/package_mod.py --check` validates the Toolkit mod structure without creating an archive. To create a developer-only archive, run `python3 tools/package_mod.py --output dist/PZSurvivorToolkit.zip`; Wishlist Lua sources are included automatically. Use `tools/prepare_install.py` to prepare both local folders, including the Java mod; it creates no archive.

To run the same checks against your installed game's native Mod Options implementation:

```sh
.venv/bin/python tools/run_tests.py --game "$PZ_GAME" --test test_highlighter
```


## Native scenarios

Use the [native runner guide](../tests/native_queue/README.md) for preparation, exclusive GUI ownership, control comparisons, runtime verdicts and coverage. The [contribution index](../tests/native_queue/contributions/README.md) lists registered adapters and their scope. Registration does not establish a native pass; use each run report and coverage matrix.

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

## Action queue adapters

Queue regression checks use the installed game's Lua queue, base action, reading action and list geometry with simulated Java/UI lifecycle. Run them with `--game "$PZ_GAME"`; without it or an explicit `--native-action-root`, those native-source checks are skipped.

For development, `ActionQueueDefinitions.lua` owns presentation entries; changing an icon or title does not grant queue permissions. Family adapters register a separate behavior with explicit nonempty `types` and `matches`/`inspect`. The type list routes candidates; it never grants permissions without a successful matcher. Include deferred command and private wait types explicitly. Matcher errors or ambiguity reject the applicable type; unrelated families are not consulted. `ActionQueuePolicy.lua` returns read-only decisions with a reason, blocker and resource; it never calls action validity callbacks. Each decision owns a lazy context for contracts and operation items, including rejected contracts; never retain or reuse that context between decisions. Direct `Policy.inspect` calls remain fresh. Use `items` for directly used item IDs and `containerOwners` for bag references through `Policy.addContainerResources`; references conflict with bag changes, not with other references. Use `dynamicInputsByType` for native moduleless item selectors, alongside full-type `dynamicInputs` where applicable. Keep future selections and unknown effects explicit, and test both a shared and an independent target before allowing edits. `ActionQueueOperations.command`/`enqueue` reuse native deferred actions. Asynchronous adapters must capture `attachContinuation(token, character)` before waiting, then use `runContinuation(handle, callback, ...)` or `finishContinuation(handle)`; `runWith` intentionally remains available for required native cleanup after cancellation. `ActionQueueCompat.lua` contains source-pinned mod adapters and native completion boundaries. Health private-handler support is pinned to the reviewed B42.21 source and remains closed when that source or its hooks differ.

Run `.venv/bin/python tools/audit_action_queue.py --native-root /path/to/media/lua --workshop-root /path/to/content/108600 --selected-ini SurvivorQoL-selected.ini --require-native --output /tmp/action-queue.json` with the test dependency Lupa installed. The generated catalog distinguishes source presence, presentation and behavior declarations; it does not claim that fixtures or live scenarios passed. Run `python3 -m unittest discover -s tests -p test_audit_action_queue.py` for the scanner checks. The Lua runner also accepts `--project-cook-picker /path/to/PJCK_CookerPicker.lua` for that UI binding. No game installation gives an explicit skip; `--require-native` makes it a failed release gate.

For local debugging, call `PZSurvivorToolkit.ActionQueuePolicy.setDiagnostics(true)` in the Lua console, exercise a move/cancel/priority request, and inspect `getDiagnostics()` on the same object. It retains at most 64 decision records in memory, including adapter, item IDs/types, source and blocker; it sends nothing externally. `setDiagnostics(false)` clears and disables it. Pending family migrations and their completion gates are in [TODO.md](../TODO.md).

Kahlua omits the standard Lua `next` global; use `pairs` and model its absence in Lua 5.1 tests. It logs failed assertions even when `pcall` catches them and does not provide reliable weak-table cleanup. Unsupported inspection paths should return unknown/protected resources without throwing. Explicitly release completed operation records, listeners and closed UI owners; include repeated queue and window lifecycle checks when changing ownership.

## Inventory selection

`InventoryRows` owns the visible-row projection for saved selection and Shift anchors. `InventoryFilter` passes its effective, possibly remapped selection through the existing restore chain, then projects it onto the final details-view rows. Preserve whole-group versus physical-child markers, CleanUI group-name identity, hidden equipment and the rendered child limit. Keep filtering and sorting in their existing owners; do not add per-mod selection-offset repairs or rebuild selection from stale `pane.items` before rendering.

## Item tag API

The shared `PZSurvivorToolkit/ItemTags` API exposes `forItem`, `forScriptItem`, `forCategory`, `label`, `matches` (all/any), bounded `normalizeRule`, `ruleActive`, `matchesRule` (all/any plus exclusions), and lossless `category` projection. Original IDs are retained to disambiguate aliases with identical tag sets; arbitrary tag combinations without a legacy equivalent return no category rather than inventing one. Unknown mod categories remain single opaque tags. Item reads follow the current instance category, including organizedCategories fluid changes. This layer does not modify native recipe `ItemTag`s, loot ScriptItems, item identities or existing category settings. Other mods continue receiving the original `getDisplayCategory()` value. Item/ScriptItem reads refine planting inputs from native farming props and full/empty packet metadata from `Base.OpenPacketOfSeeds`; category-only reads remain unchanged. Unmodified returned item-tag lists retain their exact legacy projection. These role tags do not replace native freshness, cooked/burnt or portion checks for planting. Quartermaster uses actual item tags at the public planner boundary, preserving native capacity, carrier and manual-selection behavior.

`PZSurvivorToolkit/ItemCategories` owns the optional inventory-category provider boundary. `forScript(script)` reads organizedCategories' public inventory category with a native category fallback; script tags and catalogs use it without changing the script's loot category. `prepareItem(item)` and `prepareContainer(container)` delegate fluid and instance overrides to that provider. Quartermaster calls preparation before sorting, reading picker contents and taking Manifest snapshots, so these operations do not depend on a prior inventory-pane refresh or external wrapper. `ItemTags.forItem` remains a read of the current instance category; do not replace instance-specific fluid, media or custom categories with a script/type lookup. Provider policy stays in organizedCategories; absence of the provider preserves native categories.

Audit known category IDs with `python3 tools/check_tag_categories.py --schema PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ItemTagSchema.lua --oc-root /path/to/organizedCategories_core --mod-root /path/to/selected-mod-sources --game /path/to/game-Java`. The checker compares exact IDs and reports unresolved dynamic writers. Run `python3 -m unittest discover -s tests -p test_tag_category_checker.py` for parser and CLI checks.

Use the [native tag checks](../tests/native_tags/README.md) for reconnect and cold-restart scenarios. Quartermaster's global preset-rule store has native single-player `seed` and separate-process `reload` coverage; see the [runner guidance](../tests/native_queue/README.md#files-and-contributions) for its cases and evidence requirements. This coverage is distinct from container rules and local named filters. Automated callback and persistence checks do not establish physical mouse/controller input or WAN behavior.

`QuartermasterPresets` owns the single-player preset/rule pair: `native()` and `rules()` read the published state; `transaction(fn)` supplies private draft tables and publishes them only after the existing snapshot store accepts the pair. Preset put/remove commands call it directly. Multiplayer keeps its two server ModData stores; `LootSorter_PresetSync` owns their combined request/readiness checks. `QuartermasterTagRuleAuthority` handles container-rule authorization independently of preset persistence.

Container copy/paste and `LootSorter_Picker` Save use `LootSorter.snapshotDesignation` to detach selections, including numeric preset generations. After any `QuartermasterTagRuleClient.saveBox` acceptance, `LootSorter.setBoxDesignation` writes all native fields with one object transmission and one coordinate update. It does not authorize or write tag rules. The picker owns pending-save and late-reply guards, control construction, layout, row dispatch and controller navigation. `QuartermasterTags` supplies tag rows and rule editing through explicit calls; it does not replace methods on individual picker windows. Extend the owned picker directly instead of adding a compatibility wrapper around it.

`QuartermasterCraftContainers` bounds storage availability to a crafting refresh for one player. `LootSorter_CraftMenu` scopes native `ISHandCraftPanel.updateContainers`, Neat `NC_HandCraftPanel.updateContainers`/`update`, and `NC_CraftLogicPanel.updateContainers` while preserving their original implementations. Neat's `update` has its own direct container read. Context is restored after nested calls and errors; window rendering grants no access. The fetch engine uses `inventory(player)` and suppresses storage throughout fallback input resolution. Keep these ordinary reads separate from recipe browsing so distant ingredients cannot be consumed before the physical haul. The queue compatibility proof accepts the installed getter only while it forwards unchanged, with the scope-query identity preserved.

For basic storage gameplay, the native `quartermaster-distribution` and `quartermaster-crafting` suites exercise real walking/transfers and crafting through the owned UI handlers, with exact inventory effects and Host authority. The latter uses one native fixture recipe through both ordinary and Neat crafting, including kept tools. See the [runner guidance](../tests/native_queue/README.md) for scope and commands; a transfer-only Manifest check does not establish that either complete gameplay cycle works.

## Wishlist storage

See [server setup](../MOD_INSTALL.md#server) for storage location and backup/restore requirements. Files use two alternating checked copies; global ModData is deliberately avoided because vanilla clients can request named global tables without wishlist access. Single-player uses the same validation and storage. No item, recipe or loot content is modified.

## Java development

For Java-only development, `python3 JavaPatches/build.py` produces `JavaPatches/build/PZToolkitJavaPatches`; it accepts `--game` for the directory containing both game/loader JARs, `--jdk` for JDK 25+, and `--check` for native Java regressions. The checks compare original and patched engine vehicle interpolation, vehicle ownership recovery (native collision race, validated driver/towing guards and idempotency), bounded opt-in vehicle tracing, media restart, build cancellation/completion behavior, animal location/identity/capacity reconciliation, equipment acknowledgements, hutch unloading and native string-property startup fallback (cold loader entry, IDs, values, storage and unrelated diagnostics), plus native fluid-container token normalization, fence-validation timing and early font-page loading; cart checks cover movement budgets/collision, native cadence and stop/reverse transitions, grip/grounding and wheel rolling. There is no separate zombie-speed regression in this command. Generated output is ignored by Git.

For one Java regression, use `python3 JavaPatches/build.py --test MediaChecks`; repeat `--test` to select more. When present, `--test` overrides the `--check`/`--check-video` groups; without it, those flags retain their existing behavior. `--help` lists the available test names. Each Java regression has a 120-second timeout; change it with a positive integer `--test-timeout SECONDS`. A timed-out test fails and retains its output in the reported `JavaPatches/build/<check-name>.log`. The limit applies to each test invocation, not to compilation.

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
