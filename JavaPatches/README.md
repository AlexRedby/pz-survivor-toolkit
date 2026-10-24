# Toolkit Java Patches (Experimental)

Engine fixes for **Project Zomboid B42.21**, requiring **ZombieBuddy 2.3.4+** in every client and the server. Unsupported game bytecode disables affected patches. Install the same prepared JAR everywhere and save approvals after updates. The current version comes from [build.py](build.py); changes are in the [changelog](../CHANGELOG.md#toolkit-java-patches).

Use the [combined installation guide](../MOD_INSTALL.md) for the complete mod set. This guide covers the separate Host/server loader, activation and collecting vehicle logs. Building requires JDK 25+ and Kotlin 2.4.21; playing uses the game's runtime and needs neither compiler. See [Java development](../docs/development/JAVA.md) for builds and tests.

## Included fixes

| Area | Behavior and limits |
|---|---|
| Actions, transfers and building | Safer cancellation/completion, transfer capacity checks and server acknowledgements for supported queue operations. [Scope](../docs/reference/JAVA_PATCHES.md#shared-action-lifecycle-and-outcomes). |
| Crafting | Repair the reproduced stale workstation reference that could leave progress at 100%. [Scope](../docs/reference/JAVA_PATCHES.md#workstation-crafting-references). |
| Animals | Trailer reconciliation, early equipment delivery and hutch unloading guards. These do not restore previously lost animals. [Scope](../docs/reference/JAVA_PATCHES.md#animal-trailer-reconciliation). |
| Vehicles and carts | Recover the confirmed driver-authority handoff race; support Toolkit cart control and rendering. This does not fix every desync. [Cart limits](../docs/features/VEHICLES.md#saucedcarts). |
| Media | Server VHS handling and macOS mod-video paths. [Playback setup](../MOD_INSTALL.md#tv--radio-reinvented). |
| Engine data and assets | Guarded corrections for properties, fluids, fences, fonts, a recipe icon and the stock basement hall. [Full patch reference](../docs/reference/JAVA_PATCHES.md). |

**Save dependency:** saving with the stock basement-hall key correction requires the matching patch afterward. Disabling it or loading an unsupported game build loses that hall's saved explored, lighting, spawning and roof flags. Keep backups; this is not a downgrade-safe transition. [Exact scope and legacy-save behavior](../docs/reference/JAVA_PATCHES.md#map-data-and-cross-cell-basement-rooms).

## Prepare and install

Use the [combined installation guide](../MOD_INSTALL.md#prepare-once) to build and distribute the two repository mods. The selected INI already includes this patch. [Builds and tests](../docs/development/JAVA.md#java-development) are documented separately.

## Server loader

Host starts a separate Java process. Loading ZombieBuddy only in the client does not guarantee the server VHS, workstation crafting and vehicle ownership patches are active.

### Host: save approvals first

1. Complete the [client loader setup](../MOD_INSTALL.md#zombiebuddy-loader) and install both prepared local mod folders. Subscribe to [Peek a View](https://steamcommunity.com/workshop/filedetails/?id=3710281407), [MP Vanilla Animal Trailer Sync Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3801615436) and [Animated Vehicle Parts Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3802266453) as well as ZombieBuddy so all selected Java mods are available before the first Host launch.
2. In the client's **Mods** menu enable **ZombieBuddy**, **Peek a View**, **MP Vanilla Animal Trailer Sync Fix**, **Animated Vehicle Parts Fix** and **Toolkit Java Patches (Experimental)**. Restart when asked, then approve **PeekAView**, **PZToolkitJavaPatches**, **AnimalTrailerSyncMPFix** and **AnimatedVehiclePartsFix** when prompted, choosing to **save each decision**. Do this before opening Host, and repeat when a changed JAR prompts again.
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

Find the startup line beginning **`[PZToolkitJavaPatches] Experimental B42.21 patch:`** in both client and server logs. It reports separate availability flags, including `vehicleOwnership`, `media`, `radioInventoryOff`, `build`, `video`, `animal`, `equipment`, `hutch`, `cart`, `properties`, `fluids` and `fences`. The relevant flags must be `true`; the [patch reference](../docs/reference/JAVA_PATCHES.md) lists additional per-fix checks. Also verify ZombieBuddy's actual transformation messages:

- Server: `[ZB] Transformed: zombie.vehicles.BaseVehicle`, `[ZB] Transformed: zombie.radio.devices.DeviceData` and `[ZB] Transformed: zombie.core.BuildAction`.
- Client and server item-stat decoder: `[ZB] Transformed: zombie.network.packets.ItemStatsPacket`. Omitted food values reset to the native wire defaults when a packet handler is reused.
- Each client: `[ZB] Transformed: zombie.characters.NetworkZombieAI`, `[ZB] Transformed: zombie.vehicles.VehicleInterpolation` `[ZB] Transformed: zombie.characters.NetworkPlayerAI` and `[ZB] Transformed: zombie.network.packets.EquipPacket`.
- Client and server fluid parser: `[ZB] Transformed: zombie.scripting.entity.components.fluids.FluidContainerScript`.
- Client and server property fallback: `[ZB] Transformed: zombie.core.properties.IsoPropertyType`.
- Client and server hutch guard: `[ZB] Transformed: zombie.iso.objects.IsoHutch`.
- Local cart control and pose rendering: transformations of `zombie.characters.IsoPlayer`, `zombie.characters.IsoGameCharacter` and `zombie.core.skinnedmodel.model.ModelSlotRenderData`. See [cart behavior and limits](../docs/features/VEHICLES.md#saucedcarts).

The selected Workshop `AnimalTrailerSyncMPFix` supplies a separate trailer timer fix; check `[AnimalTrailerSyncMPFix] ACTIVE` in the server log too (verified v1.3). See its [scope and installation](../docs/MODPACK.md#39-toolkit-java-patches).

These appear at the default log verbosity. Missing output, `false` values, or target-class/transformation errors mean setup is incomplete or needs investigation. The client also shows **ZombieBuddy ... loaded** in the upper-left corner. A client message alone does not confirm server activation.

## Vehicle authority recovery and diagnostic logs

Version 0.1.10 repairs an occupied vehicle whose physics owner disagrees with its confirmed server driver. A collision owner can block the normal driver handoff, and a late collision-end packet can leave the car in `Server/-1` authority while the driver remains seated. The server now reconciles authority from the live, reciprocally seated player. Towing root and trailer follow the native root driver's ownership. Empty-car collision handling, packet authorization checks and coordinates are unchanged. A matching owner is not rewritten every frame.

Install the same updated Java mod on the server and clients, save the changed JAR approval and restart them. The repair needs ZombieBuddy **in the Host child/server process**; check `vehicleOwnership=true` and the server's actual `zombie.vehicles.BaseVehicle` transformation.

**The ownership repair is active without a diagnostic flag** on supported B42.21 bytecode. To record a problem during play, open **Options > Mods > PZ Survivor Toolkit > Vehicle diagnostics** and select **Record vehicle synchronization logs**. Recording starts immediately without restarting or editing Java options. The window shows whether recording is active, off, expired or unavailable; closing it keeps recording. Uncheck to stop; select it again after a limit to start a fresh recording. This checkbox is not saved between game launches.

The window controls only that player's process. Ask each affected player to enable it. The Host child/server is a separate process: use `-Dpz.vehicle.trace=true` there for one diagnostic run, as shown below. The startup flag also remains available for clients without Toolkit's UI. It only enables logs and is not a server INI or sandbox setting.

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

`[VEHICLE_SYNC]` lines contain the side, vehicle/local-player/driver/owner IDs, authority, position, towing links, sent/received physics samples and server acceptance. `repair` records the previous authority and the new owner. Runtime toggles also write `event=session state=active/off` markers, separately from the sampled-record budget. Tracing is off by default; enabled runs stop after ten minutes from enabling or 5,000 lines, sample each event/vehicle at most once per second, and retain at most 256 sampling keys. Preserve the host/server and both client logs together. The trace does not change packets or vehicle state.

The native regression command checks the original handoff failure, reconciliation guards, idempotency, towing ownership and disabled/enabled trace bounds, alongside the existing Java patch regressions. The vehicle-recovery candidate was validated before integration with the fluid-name guard, using an isolated macOS B42.21 Host test with two connected clients and a child `GameServer -coop`, with microphone capture disabled. It reproduces the authority loss through a controlled collision/entry/release ordering. With the repair, the guest then drives 25.5 tiles with accepted server physics and matching poses on all three processes. Separate live checks cover towing/untowing and driver/passenger seat handoffs. The affected user save, spontaneous incidence and real WAN loss remain separate verification limits.

## Verification limits

Native-object checks exercise actual patched methods with fixtures; they do not verify live traversal of an existing save, natural WAN packet ordering or long sessions. Use [Java regression commands](../docs/development/JAVA.md#java-development) and the [animal-trailer fixture](../tests/native_queue/contributions/animal-trailer/README.md) for controlled early-equipment, late-trailer-snapshot and synchronization-timer scenarios.

## Test instrumentation

Programmatic silent video capture is test-only. Its API, memory limits, encoder handling and checks are in [development: test video](../docs/development/JAVA.md#test-video); the [native fixture](../tests/native_queue/contributions/video-recording/README.md) prepares a disposable profile.
