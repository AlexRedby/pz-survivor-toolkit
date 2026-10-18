# Toolkit Java Patches (Experimental)

`PZToolkitJavaPatches` is an experimental Java mod for **B42.21 only**. Its version is set in the [build definition](build.py); recorded changes are in the [changelog](../CHANGELOG.md#toolkit-java-patches). It requires **ZombieBuddy 2.3.4+** in every client and the server. Target-bytecode guards disable unsupported patches; the vehicle fix covers the reproduced authority handoff race, not every cause of vehicle desync.

## Prepare and install

Use the [combined installation guide](../MOD_INSTALL.md#prepare-once) to build and distribute the two repository mods. The selected INI already includes this patch. [Java-only builds and tests](../docs/DEVELOPMENT.md#java-development) are documented separately.

## Server loader

Host starts a separate Java process. Loading ZombieBuddy only in the client does not guarantee the server VHS, workstation crafting and vehicle ownership patches are active.

### Host: save approvals first

1. Complete the [client loader setup](../MOD_INSTALL.md#zombiebuddy-loader) and install both prepared local mod folders. Subscribe to [Peek a View](https://steamcommunity.com/workshop/filedetails/?id=3710281407) and [MP Vanilla Animal Trailer Sync Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3801615436) as well as ZombieBuddy so all selected Java mods are available before the first Host launch.
2. In the client's **Mods** menu enable **ZombieBuddy**, **Peek a View**, **MP Vanilla Animal Trailer Sync Fix** and **Toolkit Java Patches (Experimental)**. Restart when asked, then approve **PeekAView**, **PZToolkitJavaPatches** and **AnimalTrailerSyncMPFix** when prompted, choosing to **save each decision**. Do this before opening Host, and repeat when a changed JAR prompts again.
3. Close the game, leave Steam running, and launch using the appropriate command below. Then choose the configured profile in **Host**.

Saved approvals are tied to JAR content. Under normal same-account defaults, the client and Host server share `~/.zombie_buddy/mod_approvals.json` (`%USERPROFILE%\.zombie_buddy\mod_approvals.json` on Windows). Session-only approvals do not carry into the child process, whose console prompt is not exposed reliably by the Host UI. If you configure a separate ZombieBuddy `config_dir`, both processes must use the intended saved approvals.

**Windows:** from the prepared `dist/SurvivorQoL` folder, using your actual game directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-host.ps1 -Game "D:\SteamLibrary\steamapps\common\ProjectZomboid"
```

`zbNative.dll` and `ZombieBuddy.jar` must already exist there after official loader setup. The launcher checks existing game JSON loader arguments to avoid adding a second copy, then passes the loader to Host through the child process environment.

**macOS:** double-click the prepared `start-host.command`. For a non-default Steam library, run it from Terminal with the full game Java directory:

```sh
./start-host.command "/path/to/Project Zomboid.app/Contents/Java"
```

The launcher uses the game's bundled Apple Silicon or Intel runtime and passes one Java agent to the game and Host child. It bypasses the normal application launcher's JVM/Steam options. Both launchers leave system-wide environment variables and the Steam process untouched, and reject an existing ZombieBuddy agent in JVM environment options to prevent double loading.

**Linux Host:** a supplied Host launcher has not been validated for Linux. The child must inherit the loader, for example through `JDK_JAVA_OPTIONS` on a direct bundled-Java launch, with no second loader in the client JVM arguments. Use a dedicated server below if you cannot verify both processes. Do not assume client-only Steam options patch Host.

### Dedicated server

1. Put the platform's ZombieBuddy loader files in the server installation following the [official guide](https://github.com/zed-0xff/ZombieBuddy/blob/master/doc/Installation.md). Keep both local mods and the selected INI in the server account's Zomboid directory.
2. Add one loader argument to the server's JVM options, before `zombie.network.GameServer`: `-javaagent:"/full/path/ZombieBuddy.jar"` on macOS/Linux, or `-agentpath:"D:\path\zbNative.dll"` on Windows. Keep the existing server arguments. If your launcher uses a JSON `vmArgs` array, add it there using valid JSON escaping. Do not add a second loader if it is already configured.
3. Run the first start interactively under the **account that will run the server**. ZombieBuddy's dedicated-server default uses console prompts: answer `y` to allow the **PZToolkitJavaPatches** JAR, then `y` to save. Review the selected **AnimalTrailerSyncMPFix** and other Java mod prompts too. Start it as a service only after approvals are saved; repeat interactively when a changed JAR needs approval.
4. Check the server log before using it for play.

### Verify activation

Client and server logs should contain `[PZToolkitJavaPatches] Experimental B42.21 patch: zombie=true, vehicle=true, vehicleOwnership=true, media=true, build=true, video=true, animal=true, equipment=true, hutch=true, cart=true, properties=true, fluids=true, fences=true`. This confirms matching game bytecode. Also check ZombieBuddy's actual transformation messages:

- Server: `[ZB] Transformed: zombie.vehicles.BaseVehicle`, `[ZB] Transformed: zombie.radio.devices.DeviceData` and `[ZB] Transformed: zombie.core.BuildAction`.
- Each client: `[ZB] Transformed: zombie.characters.NetworkZombieAI`, `[ZB] Transformed: zombie.vehicles.VehicleInterpolation` `[ZB] Transformed: zombie.characters.NetworkPlayerAI` and `[ZB] Transformed: zombie.network.packets.EquipPacket`.
- Client and server fluid parser: `[ZB] Transformed: zombie.scripting.entity.components.fluids.FluidContainerScript`.
- Client and server property fallback: `[ZB] Transformed: zombie.core.properties.IsoPropertyType`.
- Client and server hutch guard: `[ZB] Transformed: zombie.iso.objects.IsoHutch`.
- Local cart control and pose rendering: transformations of `zombie.characters.IsoPlayer`, `zombie.characters.IsoGameCharacter` and `zombie.core.skinnedmodel.model.ModelSlotRenderData`. See [cart behavior and limits](../docs/FEATURES.md#saucedcarts).

The selected Workshop `AnimalTrailerSyncMPFix` supplies a separate trailer timer fix; check `[AnimalTrailerSyncMPFix] ACTIVE` in the server log too (verified v1.3). See its [scope and installation](../MOD_INSTALL.md#animal-trailer-fix).

These appear at the default log verbosity. Missing output, `false` values, or target-class/transformation errors mean setup is incomplete or needs investigation. The client also shows **ZombieBuddy ... loaded** in the upper-left corner. A client message alone does not confirm server activation.

## Shared action lifecycle and outcomes

Version 0.1.17 restricts incoming item-transfer cancellation to transactions owned by its connection, and prevents an absent action from being reported as completed. These corrections preserve native packet validation and effect execution.

With Toolkit 0.1.60's queue enabled, the common native completion boundary holds queue advancement until the whole `perform` callback, SP `complete` effects and Java action removal have finished. Callback errors and explicit `complete=false` fail closed. Native actions still execute through `ISTimedActionQueue`; resource contracts and required cleanup remain in place. Generator repairs use this common boundary when active and retain their earlier fallback for clients without a supported Java patch.

Native timed actions and builds receive owner/type/transaction-correlated start and terminal receipts on native ordered channel 1. Each server action instance has a UUID token. Supported selective interruption waits for both local removal and the authoritative outcome; only `canceled` permits replay. A missing result times out after 30 seconds without replay. Existing build acknowledgements and family workarounds remain available until their live SP/MP replacement gates pass. Custom mod commands and item transfers do not gain new interruption permissions from this protocol.

Verify `itemTransactions=true`, `actionManager=true`, `actionCompletion=true` and `actionAcknowledgements=true` in the activation line, plus actual `TransactionManager`, `ItemTransactionPacket`, `ActionManager` and `LuaTimedActionNew` transformations. Install and approve the same rebuilt JAR in clients and the server. The reproducible gameplay gate is `tools/check_action_queue.py run <fresh-output> --suite engine --kind sp|mp --mode toolkit --cases repair,cancel --game <game-java-directory> --jdk <jdk-25-directory> --workshop <workshop-content-108600>`; it checks real generator repair/cancellation, exact scrap IDs and an independent native reading tail.

## Build cancellation

The build acknowledgement patch lets Toolkit 0.1.30 interrupt active multiplayer construction safely. It reports the native server outcome over the same ordered channel as build transactions. Only confirmed cancellations may resume; completed builds never replay. An unsupported or unpatched server retains the queue restriction, and a missing terminal reply clears the waiting queue after 30 seconds.

## Workstation crafting references

Version 0.1.23 repairs the reproduced stale-index CraftBench decoder failure. An IsoObject's network entity ID includes its position in the square's object list. Removing an earlier object can change that ID without refreshing the server's entity registry. A workstation crafting request can then fail in `PZNetKahluaTableImpl.loadComponent` before constructing the server action, leaving client progress at 100%.

The patch refreshes only a previously registered CraftBench owner already decoded as the request's `isoObject`, with an exact match between its current square/index and the incoming component ID. It uses the native ID/registry update and leaves component decoding, constructor arguments, recipe validation, costs, outputs and duration native. It does not search for replacement workstations, recreate removed entities, suppress unrelated decoder failures or force client completion. Truly missing/unregistered objects remain outside this repair.

Install and approve the matching rebuilt Java mod on clients and the Host/server, restart and verify **`craftBench=true` in the server log**, plus `[ZB] Transformed: zombie.network.PZNetKahluaTableImpl`. The cross-platform headless regression is `python3 JavaPatches/build.py --game <game-java-directory> --jdk <jdk-25-directory> --test CraftBenchChecks`; it reproduces the original native exception and checks exact woven component/full request decoding, unchanged framing and negative guards.

The [live forge suite](../tests/native_queue/forge/README.md) reproduced the actual 100% stall in Windows Host with all 48 selected mods, unchanged native durations and the real workstation UI. The matched 0.1.23 run passed its handcraft, unchanged-forge and shifted-forge cases: one server-created blade, exactly one charcoal and iron-bar-quarter debit, preserved tool IDs and idle action/UI. Gameplay fixture bytes were identical and only the Java mod changed. No server action errors remained; seven client font-loading errors present in both runs keep the broader report `needs-review`. This does not establish clean whole-pack, macOS, WAN or two-client acceptance, nor prove that every workstation stall has this cause.

## Animal trailer reconciliation

Version 0.1.4 reconciles an animal's client trailer membership when the server reports its world, hutch or inventory location. A late trailer snapshot could previously re-add an unloaded animal permanently, leaving an entry that cannot be grabbed. Cleanup removes duplicate references to the same animal, preserves its identity and recomputes occupied trailer capacity. No animals or inventory items are created or deleted.

Install the same prepared patch folder on the server and every client, save changed JAR approvals and restart. Verify `animal=true` and the actual `zombie.characters.NetworkPlayerAI` transformation; see [activation checks](#verify-activation).

## Equipment acknowledgement race

Version 0.1.5 prevents an incomplete equipment acknowledgement from clearing a newly grabbed animal out of the player's hands when the equipment message arrives before the animal-grant message. The animal stays in inventory. Only incomplete local equipment parses omit their acknowledgement; normal updates, remote players, server handling and intentional drops retain native behavior. The demonstrated failure concerns the primary hand; unresolved secondary-only items are outside this fix.

Verify `equipment=true` and `zombie.network.packets.EquipPacket` transformation in each client log. See [decoder behavior](../docs/DEVELOPMENT.md#java-patch-boundaries) for the protocol and bytecode constraints.

## Hutch unloading crash

Version 0.1.6 guards null animal references during native `IsoHutch.removeFromWorld` cleanup in clients, single-player and servers. It preserves stored slots/counts, animal references and the original map; it creates/deletes no animals, edits no saves and does not suppress unrelated exceptions. Unsupported bytecode and custom map implementations retain native behavior. The guard does not diagnose or restore missing animals.

Install the rebuilt folder on the server and **every client, including the host**, save the changed JAR approval and restart. No new Mod ID or Workshop item is needed. Check `hutch=true` and the actual `IsoHutch` transformation. This prevents this specific unload failure; it does not restore missing animals or diagnose their original loss.

## Native string properties

Version 0.1.7 prevents five startup `IsoPropertyTypeNotFoundException` exceptions for `ladderW`, `ladderN`, `ladderE`, `ladderS` and `WindowShape`. B42.21 ships these string properties in its tile definitions but uses a throwing enum lookup before returning their original names. The patch returns those same names before the throwing lookup, preserving alias IDs, values and string storage, including the cutaway shader's `WindowShape` reads. Typed aliases supplied by other mods still use native lookup.

The mod entry point resolves the property enum before advice installation so the loader can transform it reliably. This guard requires matching `IsoPropertyType` and `TilePropertyAliasMap` bytecode. Strict enum lookup and diagnostics for every other unknown property remain native. Install the rebuilt folder on the server and every client, save the changed JAR approval and restart; verify `properties=true` and the actual `IsoPropertyType` transformation. This fix does not classify or suppress other startup errors.

## Native fluid-container names

Version 0.1.8 normalizes the two shipped `ContainerName` tokens `Large Bucket` and `Fuel Pump` before the native fluid parser validates them. Their resulting names remain `LargeBucket` and `FuelPump`; capacity, contents and other component fields retain native behavior. Every other token and its validation remain native. Matching fluid parser and script-block/value bytecode is required. Verify `fluids=true` and the actual `FluidContainerScript` transformation on clients and the server after restarting with the rebuilt JAR approved.

## Medical updates after patient disconnect

Version 0.1.15 skips only a native `BodyDamageUpdatePacket` UPDATE whose resolved patient has already disappeared on the client. B42.21 otherwise dereferences that missing player while a packet is still in flight after disconnect. Exact packet, PlayerID and packet-type class hashes guard the change. Valid updates keep native health, pain and infection parsing; START/STOP subscription packets are unchanged. This does not alter treatment effects or accept mismatched clothing synchronization packets.

The server also rejects a new `NetTimedAction` request when a serialized BodyPart belongs to a player who has already disconnected. The guard inspects only the new request’s argument table, preserves unrelated/cached actions and lets the native transaction send Reject before any Lua constructor runs. Valid medical and nonmedical requests retain native decoding; malformed unrelated payloads retain their errors. Exact decoder, transaction, player-ID and datagram-boundary bytecode is required. Check `medicalBodyDamage=true` on clients and `medicalTimedAction=true` on the server after approving the rebuilt JAR and restarting.

## Native fence validation and font pages

Version 0.1.9 leaves native fence registration, debris and gameplay methods intact. It validates sound properties after `OnLoadedTileDefinitions` callbacks finish and accepts native `FenceTypeLow` values as well as `ThumpSound`. Reset clears deferred validation. Both empty events and completed callbacks drain the validation once; queued callbacks finish on actual dispatch. The completion marker reports `Fence validation ready: checked=42, missing=2` for the shipped definitions. Unsupported or modified target bytecode retains native behavior. In 0.1.9 the shipped `carpentry_02_48/49` entries lack both properties and remain reported in the server log (the data correction in 0.1.11 is described below); no sound values or map/save data are invented.

The font patch makes the two native main-font atlas entries available before initial font construction and corrects the native Dialogue page typo. Exact font-definition, UI-pack and engine-class hashes guard the correction; existing PNG overrides and custom font definitions retain their native handling. Glyph checks compare UV coordinates and decoded alpha/RGB pixels against the shipped atlas. They do not prove GPU rendering.

**Cold-start fonts need explicit early activation of the separate `42/media/bootstrap/PZToolkitFonts.jar`.** The main `PZToolkitJavaPatches.jar` keeps its ordinary approved mod entry point. Ordinary saved mod approval does not grant ZombieBuddy's signed preload permission. For a trusted local build, append the documented `patches_jar` option to the **existing single** ZombieBuddy agent, with the JAR path before the package:

```text
-javaagent:/actual/game/ZombieBuddy.jar=patches_jar=/actual/mod/42/media/bootstrap/PZToolkitFonts.jar:net.alexredby.pztoolkitbootstrap
```

Retain any existing loader options, separating this option with a comma. Keep the entire argument as one JVM argument when paths contain spaces. A configured launcher must pass it into its client JVM before the game starts; enabling the mod later cannot repair fonts already constructed. Existing Host launch scripts do not add this option automatically. Do not edit ZombieBuddy's signed preload cache to force an unsigned JAR. Native Windows loading requires a game-relative JAR path without a drive colon because ZombieBuddy 2.3.4 splits this option at the first colon; that launch path has not been verified here. Commas and semicolons in the JAR path are unsupported.

Check `[PZToolkitJavaPatches] Early font phase enabled=true` before native font initialization, the Texture transformation and the ordinary patch activation line (`fences=true`). The normal mod phase still installs the earlier patches; the font phase loads only its Texture advice. Use the separate font JAR here: preloading the ordinary mod JAR would cause ZombieBuddy to skip its later mod entry point. The common test runner opts into the same documented loader path with `options.preload_toolkit_fonts=true`, using only its sealed selected JAR copy. Default launches remain unchanged.

## Level-three wooden fence metadata

Version 0.1.11 fills the missing `FenceTypeLow=Wood` on `carpentry_02_48/49`, the two faces of the shipped `WoodFenceLvl3` entity. Both lower wooden fence levels already carry that value. The correction requires the exact native property names, values, flags and the native `WoodFenceLvl3` entity binding; changed sprites and any existing type/sound properties remain untouched. It uses the existing alias, preserves sprite/property identities and flags, and never sets `ThumpSound`. The completion marker should report `checked=42, missing=0, corrected=2` on the stock data.

Native player/animal climb and trip selectors and furniture-break sound selection remain the same. The missing material previously prevented animals from emitting their thump sound on these two tiles; the correction enables the native `AnimalThumpGeneric` event, consistently with the lower wooden fence levels. No audio device is opened by the patch itself.

## Piano recipe icon

Version 0.1.11 supplies the missing icon metadata for the exact shipped `Base.Piano` recipe, using its existing native fallback tile `recreational_01_28`. The corrected getter returns the same texture object, atlas coordinates and pixels. It preserves the original entity component set, name, UI eligibility, recipe gameplay fields and save/network format; it does not add `UiConfig`. Explicit mod icons, custom UI configurations, changed entity data, other recipes, missing/failing client textures and unsupported bytecode retain native handling.

The native recipe loader treats icon names as inventory items and would prepend `Item_` to this world tile. A narrowly guarded script-stage hook preserves the corrected icon while leaving native input/prop validation intact, restoring the icon even when that validation throws. Resolution stays on the original script-loading thread. The client log reports `Piano recipe icon corrected: recreational_01_28` when the correction actually runs.

A dedicated server without its GUI already receives `null` from the native texture API. For this same proven Piano recipe, the patch returns that identical `null` before attempting UI resolution, without creating icon metadata, assets or texture jobs. Unrelated missing-configuration diagnostics remain visible. The font bootstrap is independent and keeps its existing explicit startup option.

## Map data and cross-cell basement rooms

Version 0.1.12 repairs the missing destination room lookup after native basement merging moves a building across a meta-cell border. The four previously reported invalid IDs in cell25,33 belong to actual native rooms in the adjacent cell25,34. Before the native merge, the patch records only rooms present by identity in the original cell's room list, runtime index and persistent-ID index. After a real cross-cell move, it restores only missing, unambiguous destination lookup entries for those same rooms. Existing entries, user-defined rooms and colliding IDs remain untouched. Room/building IDs, geometry, ordering, caches, spawn receipts and the native save format are preserved; saved flags are restored by the ordinary loader. It does not delete or rewrite `map_meta.bin`.

The exact shipped Mannequin zone at13583,1299,0 is missing its `properties` table. The patch adds an empty table after a fresh native Lua load, guarded by exact map/handler hashes, active stock map directories, target class hashes and the original row shape. It preserves sprite-derived appearance and random clothing; it does not guess a special outfit. Only the identified no-override zone receives lowest priority so overlapping custom zones registered before or after it keep their existing effect. Changed data and unrelated missing-properties diagnostics remain native.

Version 0.1.18 separates the persistent keys of the exact stock hall and its basement-access overlay at `10707,9484,0`. Both native room objects, runtime IDs, geometry, ordering, building owner and spawn receipts remain native. Before the verified merge, only the original hall receives key `0x505A0000000C00D3`; the access hall keeps `786643`. Exact engine bytecode, active stock map, lot-header/access-file hashes, room identity and unoccupied-key guards restrict the correction. Only source-verified room objects are admitted. An admitted object keeps its saved key through native recalculation and editing; unrelated new/custom objects retain native calculation. Recalculation of an admitted room refuses an occupied destination key before the native caller can overwrite another room. Check `basementHall=true` and `Basement hall key separated` after a cold start with the rebuilt JAR approved on clients and server.

**Save dependency, explicitly accepted by the user:** old duplicate-key records load through the ordinary loader with exactly the previous native result: both target the access hall and the last wins. Previously lost state is not recovered. Future native saves store two different keys. Disabling the patch or failing its guards after an update causes the native loader to skip the original hall's new key and lose that room's saved flags; an unpatched save then drops that record. This is not a downgrade-safe transition. No converter, custom trailer or restoration of the removed0.1.13 persistence machinery is included. Keep existing save backups.

The common runner retains the raw diagnostic and counts it as a known background issue only for the verified native B42.21 JAR and this exact message/origin. It does not fail a run by itself. Other coordinates, origins, builds, exceptions and unrelated diagnostics retain normal auditing. The temporary 0.1.13 implementation wrote an optional trailer that the ordinary native reader already ignores; no conversion or automatic restoration of saved files is performed. Keep any existing backups as historical data.

## Verification limits

Native-object checks exercise actual patched methods with fixtures; they do not verify live traversal of an existing save, natural WAN packet ordering or long sessions. Use [Java regression commands](../docs/DEVELOPMENT.md#java-development) and the [animal-trailer fixture](../tests/native_queue/contributions/animal-trailer/README.md) for controlled early-equipment, late-trailer-snapshot and synchronization-timer scenarios.

## Test instrumentation

Programmatic silent video capture is test-only. Its API, memory limits, encoder handling and checks are in [development: test video](../docs/DEVELOPMENT.md#test-video); the [native fixture](../tests/native_queue/contributions/video-recording/README.md) prepares a disposable profile.

## Vehicle authority recovery and diagnostic logs

Version 0.1.10 repairs an occupied vehicle whose physics owner disagrees with its confirmed server driver. A collision owner can block the normal driver handoff, and a late collision-end packet can leave the car in `Server/-1` authority while the driver remains seated. The server now reconciles authority from the live, reciprocally seated player. Towing root and trailer follow the native root driver's ownership. Empty-car collision handling, packet authorization checks and coordinates are unchanged. A matching owner is not rewritten every frame.

Install the same updated Java mod on the server and clients, save the changed JAR approval and restart them. The repair needs ZombieBuddy **in the Host child/server process**; check `vehicleOwnership=true` and the server's actual `zombie.vehicles.BaseVehicle` transformation.

**The ownership repair is active without a diagnostic flag** on supported B42.21 bytecode. `-Dpz.vehicle.trace=true` only enables logs; it is not a server INI, sandbox or Mod Options setting. Add it to the Java options of the server and every client for one diagnostic run.

**macOS Host:** from the prepared folder, a process-local setting reaches the host player and child server:

```sh
JDK_JAVA_OPTIONS=-Dpz.vehicle.trace=true ./start-host.command
```

**Windows Host:** append `"-Dpz.vehicle.trace=true"` to the existing `vmArgs` array in the game's `ProjectZomboid64.json` for the host player, keeping the loader and other arguments. Enable the child server flag only for this launch in PowerShell:

```powershell
$previousVehicleOptions = $env:JDK_JAVA_OPTIONS
try {
    $env:JDK_JAVA_OPTIONS = ($previousVehicleOptions + ' -Dpz.vehicle.trace=true').Trim()
    powershell -NoProfile -ExecutionPolicy Bypass -File .\start-host.ps1 -Game "D:\SteamLibrary\steamapps\common\ProjectZomboid"
} finally {
    $env:JDK_JAVA_OPTIONS = $previousVehicleOptions
}
```

`JDK_JAVA_OPTIONS` reaches the child Java launcher; the Windows native client uses its own JSON `vmArgs`, so configure both. **Other clients and dedicated servers:** append the same `-D` property to their JVM arguments (or JSON `vmArgs`) alongside the existing loader, before the Java main class. Restart every affected process. On macOS/Linux Steam clients, include it before the final `--` in the existing Java launch options; the supplied macOS Host helper uses the environment command above instead.

After collecting one run, remove the flag from persistent JVM/JSON/Steam options and restart. The process-local Host environment settings above do not persist between terminal sessions.

`[VEHICLE_SYNC]` lines contain the side, vehicle/local-player/driver/owner IDs, authority, position, towing links, sent/received physics samples and server acceptance. `repair` records the previous authority and the new owner. Tracing is off by default; enabled runs stop after ten minutes from the first occupied/owned vehicle or 5,000 lines, sample each event/vehicle at most once per second, and retain at most 256 sampling keys. Preserve the host/server and both client logs together. The trace does not change packets or vehicle state.

The native regression command checks the original handoff failure, reconciliation guards, idempotency, towing ownership and disabled/enabled trace bounds, alongside the existing Java patch regressions. The vehicle-recovery candidate was validated before integration with the fluid-name guard, using an isolated macOS B42.21 Host test with two connected clients and a child `GameServer -coop`, with microphone capture disabled. It reproduces the authority loss through a controlled collision/entry/release ordering. With the repair, the guest then drives 25.5 tiles with accepted server physics and matching poses on all three processes. Separate live checks cover towing/untowing and driver/passenger seat handoffs. The affected user save, spontaneous incidence and real WAN loss remain separate verification limits.
