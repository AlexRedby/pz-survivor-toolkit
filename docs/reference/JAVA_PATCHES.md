# Java patch scope and activation reference

[Development](../DEVELOPMENT.md)

For diagnosing a particular engine fix: affected behavior, bytecode guards and activation markers. Install and approve the matching JAR on clients and the server using the [Java loader guide](../../JavaPatches/README.md). Build and test commands are in [Java development](../development/JAVA.md).

- [Shared action lifecycle and outcomes](#shared-action-lifecycle-and-outcomes)
- [Build cancellation](#build-cancellation)
- [Workstation crafting references](#workstation-crafting-references)
- [Animal trailer reconciliation](#animal-trailer-reconciliation)
- [Equipment acknowledgement race](#equipment-acknowledgement-race)
- [Hutch unloading crash](#hutch-unloading-crash)
- [Native string properties](#native-string-properties)
- [Native fluid-container names](#native-fluid-container-names)
- [Medical updates after patient disconnect](#medical-updates-after-patient-disconnect)
- [Native fence validation and font pages](#native-fence-validation-and-font-pages)
- [Level-three wooden fence metadata](#level-three-wooden-fence-metadata)
- [Piano recipe icon](#piano-recipe-icon)
- [Map data and cross-cell basement rooms](#map-data-and-cross-cell-basement-rooms)

## Shared action lifecycle and outcomes

Version 0.1.17 restricts incoming item-transfer cancellation to transactions owned by its connection, and prevents an absent action from being reported as completed. These corrections preserve native packet validation and effect execution.

Version 0.1.44 includes earlier items from the same ordinary container-transfer Request in native capacity reservations. A batch that cannot fit receives the native Reject before any item moves; fitting batches retain native effects and batching. Floor and special transfer paths retain their native checks. Verify `itemBatchAdmission=true` in the **server** activation line and the `TransactionManager` transformation. This is admission-time validation; it does not roll back late native errors or changes made outside item transactions after acceptance.

With Toolkit 0.1.60's queue enabled, the common native completion boundary holds queue advancement until the whole `perform` callback, SP `complete` effects and Java action removal have finished. Callback errors and explicit `complete=false` fail closed. Native actions still execute through `ISTimedActionQueue`; resource contracts and required cleanup remain in place. Generator repairs use this common boundary when active and retain their earlier fallback for clients without a supported Java patch.

Native timed actions and builds receive owner/type/transaction-correlated start and terminal receipts on native ordered channel 1. Each server action instance has a UUID token. Supported selective interruption waits for both local removal and the authoritative outcome; only `canceled` permits replay. A missing result times out after 30 seconds without replay. Existing build acknowledgements and family workarounds remain available until their live SP/MP replacement gates pass. Custom mod commands and item transfers do not gain new interruption permissions from this protocol.

Verify `itemTransactions=true`, `actionManager=true`, `actionCompletion=true` and `actionAcknowledgements=true` in the activation line, plus actual `TransactionManager`, `ItemTransactionPacket`, `ActionManager` and `LuaTimedActionNew` transformations. Install and approve the same rebuilt JAR in clients and the server. The reproducible gameplay gate is `tools/check_action_queue.py run <fresh-output> --suite engine --kind sp|mp --mode toolkit --cases repair,cancel --game <game-java-directory> --jdk <jdk-25-directory> --workshop <workshop-content-108600>`; it checks real generator repair/cancellation, exact scrap IDs and an independent native reading tail.

## Build cancellation

The build acknowledgement patch lets Toolkit 0.1.30 interrupt active multiplayer construction safely. It reports the native server outcome over the same ordered channel as build transactions. Only confirmed cancellations may resume; completed builds never replay. An unsupported or unpatched server retains the queue restriction, and a missing terminal reply clears the waiting queue after 30 seconds.

## Workstation crafting references

Version 0.1.25 repairs the reproduced stale-index CraftBench decoder failure. An IsoObject's network entity ID includes its position in the square's object list. Removing an earlier object can change that ID without refreshing the server's entity registry. A workstation crafting request can then fail in `PZNetKahluaTableImpl.loadComponent` before constructing the server action, leaving client progress at 100%.

The patch refreshes only a previously registered CraftBench owner already decoded as the request's `isoObject`, with an exact match between its current square/index and the incoming component ID. It uses the native ID/registry update and leaves component decoding, constructor arguments, recipe validation, costs, outputs and duration native. It does not search for replacement workstations, recreate removed entities, suppress unrelated decoder failures or force client completion. Truly missing/unregistered objects remain outside this repair.

Install and approve the matching rebuilt Java mod on clients and the Host/server, restart and verify **`craftBench=true` in the server log**, plus `[ZB] Transformed: zombie.network.PZNetKahluaTableImpl`. The cross-platform headless regression is `python3 JavaPatches/build.py --game <game-java-directory> --jdk <jdk-25-directory> --test CraftBenchChecks`; it reproduces the original native exception and checks exact woven component/full request decoding, unchanged framing and negative guards.

The [live forge suite](../../tests/native_queue/forge/README.md) exercises handcraft, ordinary forge crafting and a workstation whose square object index changed. Require authoritative material/output receipts and idle action/UI state. A passing case does not establish every workstation, WAN or multi-client behavior; full runtime logs remain a separate acceptance gate.

## Animal trailer reconciliation

Version 0.1.4 reconciles an animal's client trailer membership when the server reports its world, hutch or inventory location. A late trailer snapshot could previously re-add an unloaded animal permanently, leaving an entry that cannot be grabbed. Cleanup removes duplicate references to the same animal, preserves its identity and recomputes occupied trailer capacity. No animals or inventory items are created or deleted.

Install the same prepared patch folder on the server and every client, save changed JAR approvals and restart. Verify `animal=true` and the actual `zombie.characters.NetworkPlayerAI` transformation; see [activation checks](../../JavaPatches/README.md#verify-activation).

## Equipment acknowledgement race

Version 0.1.5 prevents an incomplete equipment acknowledgement from clearing a newly grabbed animal out of the player's hands when the equipment message arrives before the animal-grant message. The animal stays in inventory. Only incomplete local equipment parses omit their acknowledgement; normal updates, remote players, server handling and intentional drops retain native behavior. The demonstrated failure concerns the primary hand; unresolved secondary-only items are outside this fix.

Verify `equipment=true` and `zombie.network.packets.EquipPacket` transformation in each client log. See [decoder behavior](../development/JAVA.md#java-patch-boundaries) for the protocol and bytecode constraints.

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

Retain any existing loader options, separating this option with a comma. Keep the entire argument as one JVM argument when paths contain spaces. A configured launcher must pass it into its client JVM before the game starts; enabling the mod later cannot repair fonts already constructed. Existing Host launch scripts do not add this option automatically. Do not edit ZombieBuddy's signed preload cache to force an unsigned JAR. Native Windows loading requires a game-relative JAR path without a drive colon because ZombieBuddy 2.3.4 splits this option at the first colon. The shared Windows Host runner now constructs this path for `options.preload_toolkit_fonts=true`; the game and snapshot must be on the same drive. Argument handling is covered by focused tests; live Windows font loading has not been verified. Commas and semicolons in the JAR path are unsupported.

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

**Save dependency:** old duplicate-key records load through the ordinary loader with exactly the previous native result: both target the access hall and the last wins. Previously lost state is not recovered. Future native saves store two different keys. Disabling the patch or failing its guards after an update causes the native loader to skip the original hall's new key and lose that room's saved flags; an unpatched save then drops that record. This is not a downgrade-safe transition. No converter, custom trailer or restoration of the removed 0.1.13 persistence machinery is included. Keep existing save backups.

The common runner retains the raw diagnostic and counts it as a known background issue only for the verified native B42.21 JAR and this exact message/origin. It does not fail a run by itself. Other coordinates, origins, builds, exceptions and unrelated diagnostics retain normal auditing. The temporary 0.1.13 implementation wrote an optional trailer that the ordinary native reader already ignores; no conversion or automatic restoration of saved files is performed. Keep any existing backups as historical data.
