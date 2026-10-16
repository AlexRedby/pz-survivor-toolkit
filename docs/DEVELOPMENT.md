# Development

[Overview](../README.md) · [Feature guide](FEATURES.md) · [Open work](../TODO.md)

Run commands below from the repository root.

## Checks and packaging

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


## Native scenarios

Use the [native runner guide](../tests/native_queue/README.md) for preparation, exclusive GUI ownership, control comparisons, runtime verdicts and coverage. The [contribution index](../tests/native_queue/contributions/README.md) lists fixtures still awaiting common-runner integration. Historical passes do not make an intake fixture ready.

## Regression scenarios

Use the checks below for the affected behavior. A fixture's assertions describe its acceptance contract; old successful runs and their assertion counts do not verify changed code. Keep native action durations when testing timing and network races; shortened reading or instant actions do not establish that coverage. Multiplayer item/resource effects require authoritative server checks, not client queue completion alone.

| Behavior | Scenario and checks |
|---|---|
| Queue cancellation and shared resources | Cancel waiting and supported active operations; remove or replace their inputs; have two clients compete for the same item IDs. Check that completed effects are not replayed, unrelated reading continues, and items/resources are conserved. See [queue regressions](../tests/test_action_queue_operations.lua) and the [native runner](../tests/native_queue/README.md). |
| Medical disconnect | Run matching native/toolkit controls with `nativeStop,remoteRemoved`, reversing doctor/patient roles. Audit clinical receipts and full runtime logs separately; a functional pass must not hide a new packet exception. The commands are in the [native runner guide](../tests/native_queue/README.md#commands); unresolved causes remain in [TODO](../TODO.md#адаптеры-ближайшего-этапа). |
| Packaged food and bulk actions | Exercise missing inputs, shared selections, cancellation, late/duplicate receipts and partial portions. Verify the exact created food ID, once-only consumption, retained completed output and borrowed-tool returns. See [packaged-food](../tests/test_packaged_food.lua) and [bulk-food](../tests/test_bulk_food.lua) regressions. |
| Crafting plans | Repeat recipes with explicit material picks and Auto, compete for a shared log, cancel a waiting plan, and reopen/resize its UI. Check source/output IDs, tool returns and preview cleanup. Use the [crafting-plan fixture](../tests/native_queue/contributions/crafting-plans/README.md). |
| Wishlist | Test concurrent edits, explicit/faction access revocation, a clean server/client restart and catalog window cleanup. Use the [Wishlist fixture](../tests/native_queue/contributions/shared-wishlist/README.md). |
| Java animal fixes | Compare unpatched/patched early equipment delivery, replay a late trailer snapshot, and compare synchronization with the timer mod absent/present. Check exact animal identities, all native grabs/drops and direct periodic sends. Use the [animal-trailer fixture](../tests/native_queue/contributions/animal-trailer/README.md). |
| UI and recording | Exercise both inventory modes, scaling, expanded stacks and repeated window close/reopen; inspect screenshots. Use the [item-tag fixture](../tests/native_queue/contributions/item-tags/README.md) and [video fixture](../tests/native_queue/contributions/video-recording/README.md). Successful callback assertions alone do not establish physical input or correct rendering. |

## Action queue adapters

Queue regression checks use the installed game's Lua queue, base action, reading action and list geometry with simulated Java/UI lifecycle. Run them with `--native-action-root /path/to/media/lua`; the default test command skips those native-source checks without that path.

For development, `ActionQueueDefinitions.lua` owns presentation entries; changing an icon or title does not grant queue permissions. Family adapters register a separate `matches`/`inspect` behavior. `ActionQueuePolicy.lua` returns read-only decisions with a reason, blocker and resource; it never calls action validity callbacks. Use `items` for directly used item IDs and `containerOwners` for bag references through `Policy.addContainerResources`; references conflict with bag changes, not with other references. Use `dynamicInputsByType` for native moduleless item selectors, alongside full-type `dynamicInputs` where applicable. Keep future selections and unknown effects explicit, and test both a shared and an independent target before allowing edits. `ActionQueueOperations.command`/`enqueue` reuse native deferred actions. Asynchronous adapters must capture `attachContinuation(token, character)` before waiting, then use `runContinuation(handle, callback, ...)` or `finishContinuation(handle)`; `runWith` intentionally remains available for required native cleanup after cancellation. `ActionQueueCompat.lua` contains source-pinned mod adapters and native completion boundaries. Health private-handler support is pinned to the reviewed B42.21 source and remains closed when that source or its hooks differ.

Run `.venv/bin/python tools/audit_action_queue.py --native-root /path/to/media/lua --workshop-root /path/to/content/108600 --selected-ini SurvivorQoL-selected.ini --require-native --output /tmp/action-queue.json` with the test dependency Lupa installed. The generated catalog distinguishes source presence, presentation and behavior declarations; it does not claim that fixtures or live scenarios passed. Run `python3 -m unittest discover -s tests -p test_audit_action_queue.py` for the scanner checks. The Lua runner also accepts `--project-cook-picker /path/to/PJCK_CookerPicker.lua` for that UI binding. No game installation gives an explicit skip; `--require-native` makes it a failed release gate.

For local debugging, call `PZSurvivorToolkit.ActionQueuePolicy.setDiagnostics(true)` in the Lua console, exercise a move/cancel/priority request, and inspect `getDiagnostics()` on the same object. It retains at most 64 decision records in memory, including adapter, item IDs/types, source and blocker; it sends nothing externally. `setDiagnostics(false)` clears and disables it. Pending family migrations and their completion gates are in [TODO.md](../TODO.md).

Kahlua logs failed assertions even when `pcall` catches them and does not provide reliable weak-table cleanup. Unsupported inspection paths should return unknown/protected resources without throwing. Explicitly release completed operation records, listeners and closed UI owners; include repeated queue and window lifecycle checks when changing ownership.

## Item tag API

The shared `PZSurvivorToolkit/ItemTags` API exposes `forItem`, `forCategory`, `label`, `matches` (all/any) and lossless `category` projection. Original IDs are retained to disambiguate aliases with identical tag sets; arbitrary tag combinations without a legacy equivalent return no category rather than inventing one. Unknown mod categories remain single opaque tags. Item reads follow the current instance category, including organizedCategories fluid changes. This layer does not modify native recipe `ItemTag`s, loot ScriptItems, item identities or existing category settings. Other mods continue receiving the original `getDisplayCategory()` value.

## Wishlist storage

See [server setup](../MOD_INSTALL.md#server) for storage location and backup/restore requirements. Files use two alternating checked copies; global ModData is deliberately avoided because vanilla clients can request named global tables without wishlist access. Single-player uses the same validation and storage. No item, recipe or loot content is modified.

## Java development

For Java-only development, `python3 JavaPatches/build.py` produces `JavaPatches/build/PZToolkitJavaPatches`; it accepts `--game` for the directory containing both game/loader JARs, `--jdk` for JDK 25+, and `--check` for native Java regressions. The checks compare original and patched engine vehicle interpolation, media restart, build cancellation/completion behavior, animal location/identity/capacity reconciliation, equipment acknowledgements and hutch unloading; there is no separate zombie-speed regression in this command. Generated output is ignored by Git.

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
