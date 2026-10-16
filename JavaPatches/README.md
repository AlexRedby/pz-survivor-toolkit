# Toolkit Java Patches (Experimental)

`PZToolkitJavaPatches` **0.1.9** is an experimental Java mod for **B42.21 only**. It requires **ZombieBuddy 2.3.4+** in every client and the server. Target-bytecode guards disable unsupported patches; this is not an established fix for minute-long vehicle freezes or every movement jerk.

## Prepare and install

Use the [combined installation guide](../MOD_INSTALL.md#prepare-once) to build and distribute the three repository mods. The selected INI already includes this patch. [Java-only builds and tests](../docs/DEVELOPMENT.md#java-development) are documented separately.

## Server loader

Host starts a separate Java process. Loading ZombieBuddy only in the client does not guarantee the server VHS patch is active.

### Host: save approvals first

1. Complete the [client loader setup](../MOD_INSTALL.md#zombiebuddy-loader) and install all three prepared local mod folders. Subscribe to [Peek a View](https://steamcommunity.com/workshop/filedetails/?id=3710281407) and [MP Vanilla Animal Trailer Sync Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3801615436) as well as ZombieBuddy so all selected Java mods are available before the first Host launch.
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

1. Put the platform's ZombieBuddy loader files in the server installation following the [official guide](https://github.com/zed-0xff/ZombieBuddy/blob/master/doc/Installation.md). Keep all three local mods and the selected INI in the server account's Zomboid directory.
2. Add one loader argument to the server's JVM options, before `zombie.network.GameServer`: `-javaagent:"/full/path/ZombieBuddy.jar"` on macOS/Linux, or `-agentpath:"D:\path\zbNative.dll"` on Windows. Keep the existing server arguments. If your launcher uses a JSON `vmArgs` array, add it there using valid JSON escaping. Do not add a second loader if it is already configured.
3. Run the first start interactively under the **account that will run the server**. ZombieBuddy's dedicated-server default uses console prompts: answer `y` to allow the **PZToolkitJavaPatches** JAR, then `y` to save. Review the selected **AnimalTrailerSyncMPFix** and other Java mod prompts too. Start it as a service only after approvals are saved; repeat interactively when a changed JAR needs approval.
4. Check the server log before using it for play.

### Verify activation

Client and server logs should contain `[PZToolkitJavaPatches] Experimental B42.21 patch: zombie=true, vehicle=true, media=true, build=true, video=true, animal=true, equipment=true, hutch=true, properties=true, fluids=true`. This confirms matching game bytecode. Also check ZombieBuddy's actual transformation messages:

- Server: `[ZB] Transformed: zombie.radio.devices.DeviceData` and `[ZB] Transformed: zombie.core.BuildAction`.
- Each client: `[ZB] Transformed: zombie.characters.NetworkZombieAI`, `[ZB] Transformed: zombie.vehicles.VehicleInterpolation` `[ZB] Transformed: zombie.characters.NetworkPlayerAI` and `[ZB] Transformed: zombie.network.packets.EquipPacket`.
- Client and server fluid parser: `[ZB] Transformed: zombie.scripting.entity.components.fluids.FluidContainerScript`.
- Client and server property fallback: `[ZB] Transformed: zombie.core.properties.IsoPropertyType`.
- Client and server hutch guard: `[ZB] Transformed: zombie.iso.objects.IsoHutch`.

The selected Workshop `AnimalTrailerSyncMPFix` supplies a separate trailer timer fix; check `[AnimalTrailerSyncMPFix] ACTIVE` in the server log too (verified v1.3). See its [scope and installation](../MOD_INSTALL.md#animal-trailer-fix).

These appear at the default log verbosity. Missing output, `false` values, or target-class/transformation errors mean setup is incomplete or needs investigation. The client also shows **ZombieBuddy ... loaded** in the upper-left corner. A client message alone does not confirm server activation.

## Build cancellation

The build acknowledgement patch lets Toolkit 0.1.30 interrupt active multiplayer construction safely. It reports the native server outcome over the same ordered channel as build transactions. Only confirmed cancellations may resume; completed builds never replay. An unsupported or unpatched server retains the queue restriction, and a missing terminal reply clears the waiting queue after 30 seconds.

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

## Native fence validation and font pages

Version 0.1.9 leaves native fence registration, debris and gameplay methods intact. It validates sound properties after `OnLoadedTileDefinitions` callbacks finish and accepts native `FenceTypeLow` values as well as `ThumpSound`. Reset clears deferred validation. Both empty events and completed callbacks drain the validation once; queued callbacks finish on actual dispatch. The completion marker reports `Fence validation ready: checked=42, missing=2` for the shipped definitions. Unsupported or modified target bytecode retains native behavior. The shipped `carpentry_02_48/49` entries still lack both properties and remain reported in the server log; no sound values or map/save data are invented.

The font patch makes the two native main-font atlas entries available before initial font construction and corrects the native Dialogue page typo. Exact font-definition, UI-pack and engine-class hashes guard the correction; existing PNG overrides and custom font definitions retain their native handling. Glyph checks compare UV coordinates and decoded alpha/RGB pixels against the shipped atlas. They do not prove GPU rendering.

**Cold-start fonts need explicit early activation of the separate `42/media/bootstrap/PZToolkitFonts.jar`.** The main `PZToolkitJavaPatches.jar` keeps its ordinary approved mod entry point. Ordinary saved mod approval does not grant ZombieBuddy's signed preload permission. For a trusted local build, append the documented `patches_jar` option to the **existing single** ZombieBuddy agent, with the JAR path before the package:

```text
-javaagent:/actual/game/ZombieBuddy.jar=patches_jar=/actual/mod/42/media/bootstrap/PZToolkitFonts.jar:net.alexredby.pztoolkitbootstrap
```

Retain any existing loader options, separating this option with a comma. Keep the entire argument as one JVM argument when paths contain spaces. A configured launcher must pass it into its client JVM before the game starts; enabling the mod later cannot repair fonts already constructed. Existing Host launch scripts do not add this option automatically. Do not edit ZombieBuddy's signed preload cache to force an unsigned JAR. Native Windows loading requires a game-relative JAR path without a drive colon because ZombieBuddy 2.3.4 splits this option at the first colon; that launch path has not been verified here. Commas and semicolons in the JAR path are unsupported.

Check `[PZToolkitJavaPatches] Early font phase enabled=true` before native font initialization, the Texture transformation and the ordinary patch activation line (`fences=true`). The normal mod phase still installs the earlier patches; the font phase loads only its Texture advice. Use the separate font JAR here: preloading the ordinary mod JAR would cause ZombieBuddy to skip its later mod entry point. The common test runner opts into the same documented loader path with `options.preload_toolkit_fonts=true`, using only its sealed selected JAR copy. Default launches remain unchanged.

## Verification limits

Native-object checks exercise actual patched methods with fixtures; they do not verify live traversal of an existing save, natural WAN packet ordering or long sessions. Use [Java regression commands](../docs/DEVELOPMENT.md#java-development) and the [animal-trailer fixture](../tests/native_queue/contributions/animal-trailer/README.md) for controlled early-equipment, late-trailer-snapshot and synchronization-timer scenarios.

## Test instrumentation

Programmatic silent video capture is test-only. Its API, memory limits, encoder handling and checks are in [development: test video](../docs/DEVELOPMENT.md#test-video); the [native fixture](../tests/native_queue/contributions/video-recording/README.md) prepares a disposable profile.
