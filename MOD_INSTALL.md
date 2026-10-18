# Install the selected mod set

For the Steam edition of Project Zomboid **B42.21**. The server and all players must use the same game build and identical local mod files.

The [server INI](SurvivorQoL-selected.ini) defines the required set. Install the current Toolkit and Java Patches from the [repository components](README.md#components); their versions are recorded in their component metadata and [changelog](CHANGELOG.md). Wishlist is part of Toolkit; its lists and Options > Mods > Survivor Wishlist settings remain available. Java Patches are experimental and target B42.21 only. Feature switches remain per-player; the action queue is enabled on fresh profiles and preserves existing preferences. See [features and limitations](docs/FEATURES.md).

Java Patches 0.1.18 gives one stock corridor a distinct persistent room key. After saving with this correction, loading without the patch (including an unsupported game update) loses that corridor's saved explored, lighting, spawning and roof flags. Keep save backups and the matching patch; see [the save dependency](JavaPatches/README.md#map-data-and-cross-cell-basement-rooms).

## Prepare once

The server owner prepares one copy for everyone. Players receiving it do not need Python or a JDK.

1. Clone or download [this repository](https://github.com/AlexRedby/pz-survivor-toolkit). Install **Python 3.10+** and **JDK 25+** on the build machine; preparation builds Toolkit and Java Patches.
2. Install the [ZombieBuddy loader](#zombiebuddy-loader) there. The game Java directory must contain both `projectzomboid.jar` and `ZombieBuddy.jar`.
3. From the repository root run `python3 tools/prepare_install.py` on macOS/Linux, or `py -3 tools/prepare_install.py` on Windows. For a custom installation add `--game "/path/to/folder-containing-both-jars"`; to choose a JDK add `--jdk "/path/to/jdk-25"`. Add `--check` to run the native Java regression checks too.
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
4. Keep the supplied order. ZombieBuddy comes first, Java Patches immediately after it, libraries before their dependants, Toolkit before CCI/MP Fast Forward/Better Containers, Realistic Dashboard before Navigator, and `organizedCategories_core` last. All local IDs are already included; do not add them to `WorkshopItems=`.
5. Set up the [server Java loader](JavaPatches/README.md#server-loader). **Host owners must complete the client steps too**, then follow [Host: save approvals first](JavaPatches/README.md#host-save-approvals-first) before using the supplied launcher. Dedicated servers also need the loader for VHS, build cancellation and vehicle authority recovery.
6. Choose `SurvivorQoL-selected` in **Host**, or start the dedicated server with `-servername SurvivorQoL-selected`. Use your existing profile name if you updated it. The Steam server downloads `WorkshopItems=` automatically; Host owners still need the client subscriptions in step 5. Separate SteamCMD Workshop downloads are unnecessary. Approve the local Java JAR for the server and check its loader log as described in the Java guide.

The INI does not transfer sandbox settings or keybindings. When moving an existing world, also copy `<profile-name>_SandboxVars.lua` under the same profile name. The supplied INI sets `SleepAllowed=true` and `SleepNeeded=false`. When copying only the mod lists, change sleep settings separately if wanted.

## Client

1. Close the game. Subscribe to [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) and wait for Steam to download it, then complete the [one-time loader setup](#zombiebuddy-loader).
2. Install the same two prepared [local mod folders](#local-mods-server-and-every-player) used by the server.
3. Start the game and join. Select **Install** at the Workshop prompt: the game downloads the remaining required items and enables the server's mods in its order. Approve **PeekAView**, **PZToolkitJavaPatches** and **AnimalTrailerSyncMPFix** when ZombieBuddy asks; save the decisions. The same JARs may need approval again after an update.
4. Configure features under **Options > Mods > PZ Survivor Toolkit**. The existing **Survivor Wishlist** settings section remains available. The action queue and prerequisite-crafting planner are optional and enabled on fresh profiles; TV and Navigator switches appear with their respective mods. Settings are local to each player and apply without restarting.
5. Set shortcuts: Toolkit highlight **F8**, Wishlist **K**, Peek a View **F9**, Better Containers Proximity Lock **F10**, Proximity Toggle **F11**, Corpse Only **F12**. Keep MP Fast Forward on **Numpad 0-4**. Disable Better Containers **Advanced Display Categories** because organizedCategories supplies them. Enable **Nested Containers Player/Loot**, keeping its multiplayer restrictions. Each player applies these preferences; the INI does not distribute them.

## ZombieBuddy loader

Install **ZombieBuddy 2.3.4+** on every client and in the server process. A Workshop subscription alone does not install the loader.

- **Windows client/Host:** use the official [ZombieBuddyInstaller.exe](https://github.com/zed-0xff/ZombieBuddy/releases/tag/windows_installer), select **Install or update ZombieBuddy**, then **Both** for normal and alternate launches. Review and apply its changes.
- **macOS / Linux client:** copy `ZombieBuddy.jar` from `steamapps/workshop/content/108600/3619862853/mods/ZombieBuddy/libs/` into the game Java directory. On macOS this is `Project Zomboid.app/Contents/Java/`; on Linux it is usually `ProjectZomboid/projectzomboid/`. Add `-javaagent:ZombieBuddy.jar --` to the game's Steam launch options. The final two hyphens are required. Follow the [author's installation guide](https://github.com/zed-0xff/ZombieBuddy/blob/master/doc/Installation.md) for launch variants.
- **Host:** leave Steam running and use the prepared `start-host.ps1` on Windows or `start-host.command` on macOS, following [these commands](JavaPatches/README.md#server-loader). They also pass the loader to Host's separate server process. A regular client-only Steam launch does not guarantee this.
- **Dedicated server:** follow the [server JVM and approval steps](JavaPatches/README.md#server-loader). Check the server log as well as the client log.

After launching the client, check for **ZombieBuddy ... loaded** in the upper-left corner. Java approval is per machine/account and JAR content; distribute the built mod folders, not another person's approval file.

## Update the set

1. Stop the server and all clients. Back up the world and `Zomboid/Lua/PZSurvivorWishlist/`. Keep this data directory and the Wishlist settings in Mod Options; they preserve Wishlist data and preferences.
2. Delete the old installed `Zomboid/mods/PZSurvivorWishlist` folder from every client, Host and dedicated-server installation. In the game's Mods menu, remove the old `PZSurvivorWishlist` Mod ID from each saved single-player profile's mod list; leave `PZSurvivorToolkit` enabled. Never load the old Wishlist folder and integrated Toolkit version together. Do not delete `Zomboid/Lua/PZSurvivorWishlist/` or the Wishlist Mod Options.
3. Update the repository and run `tools/prepare_install.py` again. Replace both local folders on the server and clients with this matching prepared version; do not merge old and new files.
4. Copy only `Mods=` and `WorkshopItems=` from the prepared INI into an existing server profile. Keep `MedicineMoodlesB42`, `TakeAnyAmount` and `TVRadioReinventedFix4220` disabled; Toolkit supplies their replacements. Keep Moodle Framework and the main TV & Radio ReInvented mod.
5. Use one installation method per Workshop mod: Steam or a complete local copy. The INI does not update local copies. Reapprove changed Java JARs when prompted on clients and the server.
6. Start and join, checking the server Java loader as above. For version mismatches, compare both local folders and Workshop updates. Keep `DoLuaChecksum=true`.

## Vehicle ownership recovery and logs

Java Patches **0.1.10** includes server recovery for the reproduced collision/driver-entry handoff race: a seated driver can lose physics authority and stop synchronizing. The server derives authority from its validated driver and preserves the towing root's ownership rules. This targets the confirmed race; it does not establish the cause of every vehicle freeze.

Replace the prepared Java mod on the server and **every client, including the host**, save the changed JAR approval and restart all processes. The Host child/server must load ZombieBuddy: verify `vehicleOwnership=true` and `[ZB] Transformed: zombie.vehicles.BaseVehicle` in the **server** log, using the [activation checks](JavaPatches/README.md#verify-activation). The repair works without an extra flag on supported bytecode.

To investigate a remaining desync, enable `-Dpz.vehicle.trace=true` in the Java options of the server and every client for one run. This flag only enables diagnostic logs; do not put it in this server INI or Mod Options. Follow the [Windows/macOS Host and dedicated/client commands](JavaPatches/README.md#vehicle-authority-recovery-and-diagnostic-logs). Collect `[VEHICLE_SYNC]` lines from both clients and the server together, including the vehicle ID and the moment the car stopped synchronizing. Tracing is off by default and bounded to ten minutes/5,000 records per process. Remove persistent diagnostic options and restart after collection.

## Animal trailer fix

Install Java Patches **0.1.15** on the server and **every client, including the host**. It includes trailer-membership and equipment-acknowledgement fixes plus the null-animal hutch-unloading guard, five native string-property startup fixes and normalization of two shipped fluid-container names. It also corrects premature fence validation and missing material metadata for the two level-three wooden fence tiles; early font loading requires the [explicit startup option](JavaPatches/README.md#native-fence-validation-and-font-pages). It also repairs cross-cell basement room lookup loss and the exact malformed stock mannequin zone; see [map data scope](JavaPatches/README.md#map-data-and-cross-cell-basement-rooms). It preserves animal identities and does not restore previously lost animals. See [patch scope](JavaPatches/README.md#animal-trailer-reconciliation).

The INI also selects [MP Vanilla Animal Trailer Sync Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3801615436), Mod ID `AnimalTrailerSyncMPFix`, Workshop ID `3801615436`, for a separate server update-timer bug that remains in B42.21. With several animals aboard, the vanilla timer permits periodic synchronization for only one animal; this mod lets every animal share the same due update. It complements the two unloading fixes. Workshop supplies it; do not copy it into the repository's local mod folders. After restarting, check `[AnimalTrailerSyncMPFix] ACTIVE` in the **server** log (verified version 1.3). If ZombieBuddy asks for its JAR approval, allow it and save the decision under the server account; Host owners do this in the client before starting Host, as described above.

Update the prepared Java mod on the **server and every client, including the host player**, approve the changed JAR and save the decision. Fully restart the server and clients. In each client's `console.txt`, check `animal=true` and `equipment=true` in `[PZToolkitJavaPatches] Experimental B42.21 patch` and the `[ZB] Transformed:` messages for both `zombie.characters.NetworkPlayerAI` and `zombie.network.packets.EquipPacket` (they may say `retransformed`). Try Grab and then put the animal on the ground; the trailer entry should disappear for everyone.

For the hutch guard, also verify `hutch=true` and `[ZB] Transformed: zombie.iso.objects.IsoHutch` in each client log. Save changed JAR approvals and restart all processes after updates. A Host client crash also shuts down its server.

If an animal is still stuck, preserve the save and collect server/client logs around one Grab attempt before deleting or replacing it. Use the [animal-trailer regression scenarios](docs/DEVELOPMENT.md#regression-scenarios) to reproduce packet-ordering and timer issues in a disposable profile.

## TV & Radio ReInvented

The INI includes the main `TVRadio_ReInvented` mod. Toolkit fixes device recognition on EN/RU clients and the native macOS video path; do not enable the separate `TVRadioReinventedFix4220`.

- **macOS:** install the complete TV mod, including `.bik` files in `42/media/videos/`. A matching Toolkit Java Patches build resolves requests from the active mod directory before native caching, so no separate `Project Zomboid.app/workshop` symlink is needed.
- **Linux/SteamOS:** the former external fix describes a `steamapps/common/workshop` link in its [path instructions](https://steamcommunity.com/sharedfiles/filedetails/?id=3796050675). Toolkit's automatic path fix targets macOS; playback on Linux/SteamOS and Windows/Proton was not verified in that scenario.

## Player controls

See [features and controls](docs/FEATURES.md) for Wishlist sharing, TV/VHS actions, nested-bag restrictions, queue behavior and per-player settings. Use [development scenarios](docs/DEVELOPMENT.md#regression-scenarios) to check a changed installation.
