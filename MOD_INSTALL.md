# Install the selected mod set

For the Steam edition of Project Zomboid **B42.21**. The server and all players must use the same game build and identical local mod files.

The [server INI](SurvivorQoL-selected.ini) defines the required set. Install the current Toolkit and Java Patches from the [repository components](README.md#components); their versions are recorded in their component metadata and [changelog](CHANGELOG.md). Wishlist and the complete Quartermaster feature set are part of Toolkit, including sorting, presets, crafting and the storage manifest. Their existing data and settings remain available. Java Patches are experimental and target B42.21 only. Feature switches remain per-player; the action queue is enabled on fresh profiles and preserves existing preferences. See [features and limitations](docs/FEATURES.md).

Java Patches 0.1.18 gives one stock corridor a distinct persistent room key. After saving with this correction, loading without the patch (including an unsupported game update) loses that corridor's saved explored, lighting, spawning and roof flags. Keep save backups and the matching patch; see [the save dependency](JavaPatches/README.md#map-data-and-cross-cell-basement-rooms).

## Prepare once

The server owner prepares one copy for everyone. Players receiving it do not need Python, a JDK or a Kotlin installation; the Kotlin runtime is bundled in the Java mod JAR.

1. Clone or download [this repository](https://github.com/AlexRedby/pz-survivor-toolkit). Install **Python 3.10+**, **JDK 25+** and unpack the [Kotlin 2.4.21 compiler distribution](https://github.com/JetBrains/kotlin/releases/tag/v2.4.21) on the build machine; preparation builds Toolkit and Java Patches. Point `KOTLIN_HOME` to the distribution root containing `lib/` (not `bin/`); the build prefers `--kotlin-home`, then `KOTLIN_HOME`, then `kotlinc` on `PATH`.
2. Install the [ZombieBuddy loader](#zombiebuddy-loader) there. The game Java directory must contain both `projectzomboid.jar` and `ZombieBuddy.jar`.
3. From the repository root run `python3 tools/prepare_install.py` on macOS/Linux, or `py -3 tools/prepare_install.py` on Windows. For a custom installation add `--game "/path/to/folder-containing-both-jars"`; to choose a JDK add `--jdk "/path/to/jdk-25"`. To select Kotlin explicitly add `--kotlin-home "/path/to/kotlinc"`. The build requires compiler and stdlib version 2.4.21 and downloads nothing; a missing or mismatched compiler fails preparation. Add `--check` to run the native JVM regression checks too.
4. Give every player the generated **dist/SurvivorQoL** folder. It contains `mods/PZSurvivorToolkit`, `mods/PZToolkitJavaPatches`, `Server/SurvivorQoL-selected.ini`, the Windows/macOS Host launchers, this installation guide and `JavaPatches/README.md`. It contains repository mods only; Workshop supplies the rest. Generated output is ignored by Git, uncompressed, and safely replaced on the next successful preparation. Live game files and profiles are untouched.

## Local mods: server and every player

With the game/server stopped, copy the **two entire folders inside the prepared `mods` folder** into `Zomboid/mods`. Keep their `common` and `42` subfolders. Check that each has `42/mod.info`; avoid double nesting such as `PZSurvivorToolkit/PZSurvivorToolkit`.

| Platform | Zomboid directory |
|---|---|
| Windows | `%USERPROFILE%\Zomboid` |
| macOS / Linux | `~/Zomboid` |
| Dedicated server | `Zomboid` in the home directory of the account running the server; use the specified directory when launching with `-cachedir` |

These local mods have no Workshop items and **do not download when joining**. Distribute the same prepared folders to everyone. If switching a Workshop mod from a local copy to Steam downloads, move its old local folder out of `Zomboid/mods` so it does not override the download.

## Server

1. Stop the server. Back up the world and an existing profile's INI. Include `Zomboid/Lua/PZSurvivorWishlist/` in backups: shared lists are stored there separately from the world, under its encoded save path. Keep that save path when restoring.
2. Install both [local mod folders](#local-mods-server-and-every-player).
3. For a **new profile**, copy the prepared `Server/SurvivorQoL-selected.ini` into `Zomboid/Server`. For an **existing profile**, copy only the `Mods=` and `WorkshopItems=` lines into its existing INI; keep its other settings.
4. Keep the supplied order. ZombieBuddy comes first, Java Patches immediately after it, libraries before their dependants, CleanUI before Toolkit, Toolkit before MP Fast Forward/Better Containers, Realistic Dashboard before Navigator, and `organizedCategories_core` last. All local IDs are already included; do not add them to `WorkshopItems=`.
5. Set up the [server Java loader](JavaPatches/README.md#server-loader). **Host owners must complete the client steps too**, then follow [Host: save approvals first](JavaPatches/README.md#host-save-approvals-first) before using the supplied launcher. Dedicated servers also need the loader for VHS, build cancellation and vehicle authority recovery.
6. Choose `SurvivorQoL-selected` in **Host**, or start the dedicated server with `-servername SurvivorQoL-selected`. Use your existing profile name if you updated it. The Steam server downloads `WorkshopItems=` automatically; Host owners still need the client subscriptions in step 5. Separate SteamCMD Workshop downloads are unnecessary. Approve the local Java JAR for the server and check its loader log as described in the Java guide.

The selected vehicle visuals are **Vanilla Vehicles Animated** (`VanillaVehiclesAnimated`, Workshop `3281755175`) and **Animated Vehicle Parts Fix** (`AnimatedVehiclePartsFix`, Workshop `3802266453`). Workshop supplies both. The fix requires the existing ZombieBuddy loader and saved JAR approval on the client; its author describes the offscreen animation bug as single-player only. VVA animations between Host players remain unverified; the outdated `VASinked` addon is not selected. Optional VVA submods are disabled. See [the catalog](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/USEFUL_MODS.md#46-vanilla-vehicles-animated) for the visual changes and limitations.

The INI does not transfer sandbox settings or keybindings. When moving an existing world, also copy `<profile-name>_SandboxVars.lua` under the same profile name. The supplied INI sets `SleepAllowed=true` and `SleepNeeded=false`. When copying only the mod lists, change sleep settings separately if wanted.

## Selected QoL additions

The selected set also includes Detailed Skill Tooltips (`EURY_DST`, Workshop `3572846242`), Foraging Tooltip Extended (`Ivmakk_ForagingTooltipExtended`, `3507997225`) and Custom Light Switch (`CustomLightSwitch`, `3779343349`). The supplied INI includes all three; no extra framework is required by their author pages. Skill/foraging displays use their own Mod Options. Custom Light Switch adds a learnable construction recipe and room lighting. Their full-pack B42.21 SP/Host behavior remains unverified; check them in a disposable profile before using a gameplay world. See the [catalog](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/USEFUL_MODS.md#49-detailed-skill-tooltips) for features and limits.

Nick's Turn Off Fridges (`NicksTurnOffFridges`, Workshop `3778868211`) is also included. Use the appliance context menu to unplug/replug; Auto-Unplug is optional per appliance. **Plug every fridge/freezer back in before removing this mod**, because its unplugged state persists on the appliance. B42.21 full-pack SP/Host behavior remains unverified; see the [catalog](https://github.com/AlexRedby/pz-survivor-toolkit/blob/main/USEFUL_MODS.md#52-nicks-turn-off-fridges).

## Client

1. Close the game. Subscribe to [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) and wait for Steam to download it, then complete the [one-time loader setup](#zombiebuddy-loader).
2. Install the same two prepared [local mod folders](#local-mods-server-and-every-player) used by the server.
3. Start the game and join. Select **Install** at the Workshop prompt: the game downloads the remaining required items and enables the server's mods in its order. Approve **PeekAView**, **PZToolkitJavaPatches**, **AnimalTrailerSyncMPFix** and **AnimatedVehiclePartsFix** when ZombieBuddy asks; save the decisions. The same JARs may need approval again after an update.
4. Configure features under **Options > Mods > PZ Survivor Toolkit**. The existing **Survivor Wishlist** settings section remains available. Inventory preferences are under **Toolkit Item Details** and **Toolkit: Container Capacity**; previous Item Details/CCI preferences are retained. **Toolkit: Planting information** retains Seed Season Indicator preferences. The action queue and prerequisite-crafting planner are optional and enabled on fresh profiles; TV and Navigator switches appear with their respective mods. Settings are local to each player and apply without restarting.
5. Set shortcuts: Toolkit highlight **F8**, Wishlist **K**, Peek a View **F9**, Better Containers Proximity Lock **F10**, Proximity Toggle **F11**, Corpse Only **F12**. Keep MP Fast Forward on **Numpad 0-4**. Disable Better Containers **Advanced Display Categories** because organizedCategories supplies them. Enable **Nested Containers Player/Loot**, keeping its multiplayer restrictions. Each player applies these preferences; the INI does not distribute them.

## ZombieBuddy loader

Install **ZombieBuddy 2.3.4+** on every client and in the server process. A Workshop subscription alone does not install the loader.

- **Windows client/Host:** use the official [ZombieBuddyInstaller.exe](https://github.com/zed-0xff/ZombieBuddy/releases/tag/windows_installer), select **Install or update ZombieBuddy**, then **Both** for normal and alternate launches. Review and apply its changes.
- **macOS / Linux client:** copy `ZombieBuddy.jar` from `steamapps/workshop/content/108600/3619862853/mods/ZombieBuddy/libs/` into the game Java directory. On macOS this is `Project Zomboid.app/Contents/Java/`; on Linux it is usually `ProjectZomboid/projectzomboid/`. Add `-javaagent:ZombieBuddy.jar --` to the game's Steam launch options. The final two hyphens are required. Follow the [author's installation guide](https://github.com/zed-0xff/ZombieBuddy/blob/master/doc/Installation.md) for launch variants.
- **Host:** leave Steam running and use the prepared `start-host.ps1` on Windows or `start-host.command` on macOS, following [these commands](JavaPatches/README.md#server-loader). They also pass the loader to Host's separate server process. A regular client-only Steam launch does not guarantee this.
- **Dedicated server:** follow the [server JVM and approval steps](JavaPatches/README.md#server-loader). Check the server log as well as the client log.

After launching the client, check for **ZombieBuddy ... loaded** in the upper-left corner. Java approval is per machine/account and JAR content; distribute the built mod folders, not another person's approval file.

## Update the set

1. Stop the server and all clients. Back up the world and `Zomboid/Lua/`, including Wishlist data, `QuartermasterPresets.txt`, `PZSTQuartermasterPresets_a.txt`, `PZSTQuartermasterPresets_b.txt` and `PZSTQuartermasterTagRules.txt` when present. Keep these files and both mods' existing settings; they preserve lists, sorting presets and preferences. Container designations stay in the world save.
2. Delete the old installed `Zomboid/mods/PZSurvivorWishlist` folder from every client, Host and dedicated-server installation. In the game's Mods menu, remove the old `PZSurvivorWishlist` Mod ID from each saved single-player profile's mod list; leave `PZSurvivorToolkit` enabled. Never load the old Wishlist folder and integrated Toolkit version together. Do not delete `Zomboid/Lua/PZSurvivorWishlist/` or the Wishlist Mod Options.
3. Update the repository and run `tools/prepare_install.py` again. Replace both local folders on the server and clients with this matching prepared version; do not merge old and new files.
4. Copy only `Mods=` and `WorkshopItems=` from the prepared INI into an existing server profile. Remove the separate `Quartermaster` Mod ID and Workshop item `3761216758` from existing server and single-player mod lists; disable any local Quartermaster copy before loading the updated Toolkit. Do not load both copies together or delete their saved data. Also disable `ContainerCapacityIndicator` (`3789660055`) and `BravoItemDetails` (`3477237184`) in existing profiles; Toolkit now owns their display and sorting functions. Also disable `HasResearch` (`3567695139`) and `SeedSeasonIndicator` (`3734639991`); Toolkit provides their indicators and growing information. Keep saved Mod Options preferences. Keep `MedicineMoodlesB42`, `TakeAnyAmount` and `TVRadioReinventedFix4220` disabled; Toolkit supplies their replacements. Keep Moodle Framework and the main TV & Radio ReInvented mod.
5. Use one installation method per Workshop mod: Steam or a complete local copy. The INI does not update local copies. Reapprove changed Java JARs when prompted on clients and the server.
6. Start and join, checking the server Java loader as above. For version mismatches, compare both local folders and Workshop updates. Keep `DoLuaChecksum=true`.

## Vehicle ownership recovery and logs

Java Patches **0.1.10** includes server recovery for the reproduced collision/driver-entry handoff race: a seated driver can lose physics authority and stop synchronizing. The server derives authority from its validated driver and preserves the towing root's ownership rules. This targets the confirmed race; it does not establish the cause of every vehicle freeze.

Replace the prepared Java mod on the server and **every client, including the host**, save the changed JAR approval and restart all processes. The Host child/server must load ZombieBuddy: verify `vehicleOwnership=true` and `[ZB] Transformed: zombie.vehicles.BaseVehicle` in the **server** log, using the [activation checks](JavaPatches/README.md#verify-activation). The repair works without an extra flag on supported bytecode.

To investigate a remaining desync, enable `-Dpz.vehicle.trace=true` in the Java options of the server and every client for one run. This flag only enables diagnostic logs; do not put it in this server INI or Mod Options. Follow the [Windows/macOS Host and dedicated/client commands](JavaPatches/README.md#vehicle-authority-recovery-and-diagnostic-logs). Collect `[VEHICLE_SYNC]` lines from both clients and the server together, including the vehicle ID and the moment the car stopped synchronizing. Tracing is off by default and bounded to ten minutes/5,000 records per process. Remove persistent diagnostic options and restart after collection.

## Animal trailer fix

Install the current prepared Java mod on the server and **every client, including the host**. Its trailer-membership, equipment-acknowledgement and hutch-unloading corrections preserve animal identities and do not restore previously lost animals. See [patch scope](JavaPatches/README.md#animal-trailer-reconciliation) for these fixes and the other engine corrections included in the same component.

The INI also selects [MP Vanilla Animal Trailer Sync Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3801615436), Mod ID `AnimalTrailerSyncMPFix`, Workshop ID `3801615436`, for a separate server update-timer bug that remains in B42.21. With several animals aboard, the vanilla timer permits periodic synchronization for only one animal; this mod lets every animal share the same due update. It complements the two unloading fixes. Workshop supplies it; do not copy it into the repository's local mod folders. After restarting, check `[AnimalTrailerSyncMPFix] ACTIVE` in the **server** log (verified version 1.3). If ZombieBuddy asks for its JAR approval, allow it and save the decision under the server account; Host owners do this in the client before starting Host, as described above.

Update the prepared Java mod on the **server and every client, including the host player**, approve the changed JAR and save the decision. Fully restart the server and clients. In each client's `console.txt`, check `animal=true` and `equipment=true` in `[PZToolkitJavaPatches] Experimental B42.21 patch` and the `[ZB] Transformed:` messages for both `zombie.characters.NetworkPlayerAI` and `zombie.network.packets.EquipPacket` (they may say `retransformed`). Try Grab and then put the animal on the ground; the trailer entry should disappear for everyone.

For the hutch guard, also verify `hutch=true` and `[ZB] Transformed: zombie.iso.objects.IsoHutch` in each client log. Save changed JAR approvals and restart all processes after updates. A Host client crash also shuts down its server.

If an animal is still stuck, preserve the save and collect server/client logs around one Grab attempt before deleting or replacing it. Use the [animal-trailer regression scenarios](docs/DEVELOPMENT.md#regression-scenarios) to reproduce packet-ordering and timer issues in a disposable profile.

## Archery

The selected set includes [Archery Nexus](https://steamcommunity.com/sharedfiles/filedetails/?id=3617854007) (`3617854007`, `ArcheryNexus`) followed by [Wilderness Progression: Archery Nexus](https://steamcommunity.com/sharedfiles/filedetails/?id=3776221203) (`3776221203`, `WildernessProgressionArcheryNexusCompanion`). Keep both Workshop items and Mod IDs on Host and clients, with the base before the companion. Do not enable Archery Nexus Fixed or Lite alongside the companion. RadArchery and the RadBows Upgrade are not required or selected.

The companion adds Archery progression, material-specific arrow crafting/recovery, bowstring wear and endurance/arm-strain costs while drawing. Its baseline Wilderness Progression sandbox settings use damage/range `1` and Normal endurance drain/muscle strain. The INI does not apply these settings to an existing world; retain that world's sandbox settings unless deliberately changing them.

**Not yet gameplay-verified with this pack on B42.21.** The author includes multiplayer support but says live testing is incomplete. Before using an existing world, back it up and check crafting, firing, arrow recovery/breakage, restringing and equipment changes in a separate test profile; for Host, also check remote shots and matching arrow counts on client and server. Toolkit queue and crafting integrations are not established by selecting these mods. Repository selection alone does not install the Workshop files or alter a live profile.

## TV & Radio ReInvented

The INI includes the main `TVRadio_ReInvented` mod. Toolkit fixes device recognition on EN/RU clients and the native macOS video path; do not enable the separate `TVRadioReinventedFix4220`.

- **macOS:** install the complete TV mod, including `.bik` files in `42/media/videos/`. A matching Toolkit Java Patches build resolves requests from the active mod directory before native caching, so no separate `Project Zomboid.app/workshop` symlink is needed.
- **Linux/SteamOS:** the former external fix describes a `steamapps/common/workshop` link in its [path instructions](https://steamcommunity.com/sharedfiles/filedetails/?id=3796050675). Toolkit's automatic path fix targets macOS; playback on Linux/SteamOS and Windows/Proton was not verified in that scenario.

## Player controls

See [features and controls](docs/FEATURES.md) for Wishlist sharing, TV/VHS actions, nested-bag restrictions, queue behavior and per-player settings. Use [development scenarios](docs/DEVELOPMENT.md#regression-scenarios) to check a changed installation.
