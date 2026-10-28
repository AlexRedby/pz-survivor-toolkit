# Install the selected mod set

For the Steam edition of **Project Zomboid B42.21**, in single-player or **Host** from the game menu. The Host and all players need the same game build, local mod files and Workshop selection. Java Patches are experimental and support B42.21 only.

| Your task | Start here |
|---|---|
| I received the prepared `SurvivorQoL` folder | [Client setup](#client) |
| I host the game | [Client setup](#client), then [server profile](#server) and [Host loader/approvals](JavaPatches/README.md#host-save-approvals-first) |
| I need to create the folder for everyone | [Prepare once](#prepare-once), then distribute it |
| I already use an older version | [Update the set](#update-the-set) |
| The loader or a vehicle fix seems inactive | [Activation checks](JavaPatches/README.md#verify-activation) and [vehicle logs](JavaPatches/README.md#vehicle-authority-recovery-and-diagnostic-logs) |

The [server INI](SurvivorQoL-selected.ini) defines the selection. Toolkit and Java Patches have no Workshop download. All third-party mods, including CleanUI, NewMusic and that DAMN Library, come from Workshop. Toolkit controls the NewMusic compatibility changes without a separate NewMusic copy. [Current versions and changes](CHANGELOG.md) come from the component metadata linked in the [overview](README.md#components). Options are per player; see [features and controls](docs/FEATURES.md).

**Back up an existing world before changing its mods.** The Java patch gives one stock corridor a distinct persistent room key. Saving with this correction requires the matching patch afterward; disabling it or loading an unsupported game build loses that corridor's saved explored, lighting, spawning and roof flags. See [the save dependency](JavaPatches/README.md#included-fixes).

## Client

1. Close the game. Subscribe to [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) and wait for Steam to download it, then complete the [one-time loader setup](#zombiebuddy-loader).
2. Install the same prepared [local mod folders](#local-mods-server-and-every-player) used by the server.
3. Choose the client route: **joining a Host/server** downloads and enables its Workshop selection when you select **Install** at the join prompt. For **single-player or your first Host launch**, subscribe to the selected Workshop items using the [catalog](docs/MODPACK.md), wait for downloads and enable the selected client mods. Use the INI order; the Host server profile is configured [below](#server).
4. Approve **PeekAView**, **PZToolkitJavaPatches**, **AnimalTrailerSyncMPFix** and **AnimatedVehiclePartsFix** when ZombieBuddy asks; save each decision. A changed JAR may require approval again after an update. Before using Host, follow its [first-launch approval steps](JavaPatches/README.md#host-save-approvals-first). Test a changed single-player setup in a separate save before loading your gameplay world.
5. Configure features under **Options > Mods > PZ Survivor Toolkit**. The existing **Survivor Wishlist** settings section remains available. Inventory preferences are under **Toolkit Item Details** and **Toolkit: Container Capacity**; previous Item Details/CCI preferences are retained. **Toolkit: Planting information** retains Seed Season Indicator preferences. The action queue and prerequisite-crafting planner are optional and enabled on fresh profiles; TV and Navigator switches appear with their respective mods. Settings are local to each player and apply without restarting.
6. Set shortcuts: Toolkit highlight **F8**, Wishlist **K**, Peek a View **F9**, Better Containers Proximity Lock **F10**, Proximity Toggle **F11**, Corpse Only **F12**. Keep MP Fast Forward on **Numpad 0-4**. Disable Better Containers **Advanced Display Categories** because Toolkit supplies item classification. Enable **Nested Containers Player/Loot**, keeping its multiplayer restrictions. Each player applies these preferences; the INI does not distribute them.

## Local mods: server and every player

With the game/server stopped, copy **both complete folders inside the prepared `mods` folder** (`PZSurvivorToolkit`, `PZToolkitJavaPatches`) into `Zomboid/mods`. Keep every version and `common` subfolder. Both mods use `42/mod.info`. Check these metadata files; avoid double nesting such as `PZSurvivorToolkit/PZSurvivorToolkit`.

| Platform | Zomboid directory |
|---|---|
| Windows | `%USERPROFILE%\Zomboid` |
| macOS / Linux | `~/Zomboid` |
| Dedicated server | `Zomboid` in the home directory of the account running the server; use the specified directory when launching with `-cachedir` |

The prepared folders **do not download when joining**. Distribute the same two local mod folders to everyone. Download every third-party dependency, including CleanUI, NewMusic and that DAMN Library, from Workshop; do not install separate patched copies of those dependencies.

## ZombieBuddy loader

Install **ZombieBuddy 2.3.4+** on every client and in the server process. A Workshop subscription alone does not install the loader.

- **Windows client/Host:** use the official [ZombieBuddyInstaller.exe](https://github.com/zed-0xff/ZombieBuddy/releases/tag/windows_installer), select **Install or update ZombieBuddy**, then **Both** for normal and alternate launches. Review and apply its changes.
- **macOS / Linux client:** copy `ZombieBuddy.jar` from `steamapps/workshop/content/108600/3619862853/mods/ZombieBuddy/libs/` into the game Java directory. On macOS this is `Project Zomboid.app/Contents/Java/`; on Linux it is usually `ProjectZomboid/projectzomboid/`. Add `-javaagent:ZombieBuddy.jar --` to the game's Steam launch options. The final two hyphens are required. Follow the [author's installation guide](https://github.com/zed-0xff/ZombieBuddy/blob/master/doc/Installation.md) for launch variants.
- **Host:** with Java Patches 0.1.58+ enabled in the client and Host profile, launch normally through Steam. Toolkit supplies ZombieBuddy to Host's separate server process automatically. Save JAR approvals before hosting and check [both processes](JavaPatches/README.md#server-loader); special Host/vehicle-trace launchers are no longer required. Diagnostics are controlled in-game.
- **Dedicated server:** follow the [server JVM and approval steps](JavaPatches/README.md#server-loader). Check the server log as well as the client log.

After launching the client, check for **ZombieBuddy ... loaded** in the upper-left corner. Java approval is per machine/account and JAR content; distribute the built mod folders, not another person's approval file.

## Server

1. Stop the server. Back up the world and an existing profile's INI. Include `Zomboid/Lua/PZSurvivorWishlist/` in backups: shared lists are stored there separately from the world, under its encoded save path. Keep that save path when restoring.
2. Install both [local mod folders](#local-mods-server-and-every-player).
3. For a **new profile**, copy the prepared `Server/SurvivorQoL-selected.ini` into `Zomboid/Server`. For an **existing profile**, copy only the `Mods=` and `WorkshopItems=` lines into its existing INI; keep its other settings.
4. Keep the supplied order. ZombieBuddy comes first, Java Patches immediately after it, libraries before their dependants, CleanUI before Toolkit, Toolkit before MP Fast Forward/Better Containers, and Realistic Dashboard before Navigator. All local IDs are already included; do not add them to `WorkshopItems=`.
5. Set up the [server Java loader](JavaPatches/README.md#server-loader). **Host owners must complete the client steps too**, then follow [Host: save approvals first](JavaPatches/README.md#host-save-approvals-first) before using the supplied launcher. Dedicated servers also need the loader for VHS, build cancellation and vehicle authority recovery.
6. Choose `SurvivorQoL-selected` in **Host**, or start the dedicated server with `-servername SurvivorQoL-selected`. Use your existing profile name if you updated it. The Steam server downloads `WorkshopItems=` automatically; Host owners must finish client subscriptions and saved approvals before their first Host launch. Separate SteamCMD Workshop downloads are unnecessary. Approve the local Java JAR for the server and check its loader log as described in the Java guide.

The INI does not transfer sandbox settings or keybindings. When moving an existing world, also copy `<profile-name>_SandboxVars.lua` under the same profile name. The supplied INI sets `SleepAllowed=true` and `SleepNeeded=false`. When copying only the mod lists, change sleep settings separately if wanted.

Third-party dependencies, settings and limitations are in the [selected mod catalog](docs/MODPACK.md). The INI supplies load order, not per-player shortcuts or sandbox settings. Archery and several recent additions still require full-pack SP/Host checks; selection alone does not establish compatibility.

## Prepare once

The server owner prepares one copy for everyone. Players receiving it do not need Python, a JDK or a Kotlin installation. The patch targets Java 25, provided by the supported B42.21 game runtime; its private Kotlin runtime is bundled in the mod JAR.

1. Clone or download [this repository](https://github.com/AlexRedby/pz-survivor-toolkit). Install **Python 3.10+**, **JDK 25+** and unpack the [Kotlin 2.4.21 compiler distribution](https://github.com/JetBrains/kotlin/releases/tag/v2.4.21) on the build machine; preparation builds Toolkit and Java Patches. Point `KOTLIN_HOME` to the distribution root containing `lib/` (not `bin/`); the build prefers `--kotlin-home`, then `KOTLIN_HOME`, then `kotlinc` on `PATH`.
2. Install the [ZombieBuddy loader](#zombiebuddy-loader) there. The game Java directory must contain both `projectzomboid.jar` and `ZombieBuddy.jar`.
3. From the repository root run `python3 tools/prepare_install.py` on macOS/Linux, or `py -3 tools/prepare_install.py` on Windows. Preparation builds and copies only Toolkit and Java Patches; it requires no third-party source folders. For a custom installation add `--game "/path/to/folder-containing-both-jars"`; to choose a JDK add `--jdk "/path/to/jdk-25"`. To select Kotlin explicitly add `--kotlin-home "/path/to/kotlin-distribution"`. The build requires compiler and stdlib version 2.4.21 and downloads nothing; a missing or mismatched compiler fails preparation. Add `--check` to run the native JVM regression checks too.
4. Give every player the generated **dist/SurvivorQoL** folder. It contains only `mods/PZSurvivorToolkit` and `mods/PZToolkitJavaPatches` as mods, plus `Server/SurvivorQoL-selected.ini`, optional legacy Windows/macOS Host launchers, this installation guide and `JavaPatches/README.md`. Workshop supplies all third-party dependencies. Generated output is ignored by Git, uncompressed, and safely replaced on the next successful preparation. Live game files and profiles are untouched.

## Vehicle diagnostics

Before driving, open **Options > Mods > PZ Survivor Toolkit > Vehicle diagnostics**. The Host owner enables both **Record traces on this client** and **Record traces on the Host server**, then waits for **Recording is active** for both sides. Each other affected player enables their own **Record traces on this client**. Both switches work during play without Java flags or restarting; guests cannot control server recording. A server timeout means its recording state is unknown. Follow the [complete Host/client collection steps](JavaPatches/README.md#vehicle-authority-recovery-and-diagnostic-logs).

Recording continues until manually stopped or the process exits. Files rotate at 5 MiB with four backups (25 MiB per side), under the current profile's `Logs/PZToolkitVehicleTrace/client`, `server` or `sp` folder. The field below each switch shows its exact file path. Preserve the current `vehicle-sync.log` and its `.1` to `.4` backups from all affected sides; the oldest history is discarded during rotation. Samples are no longer duplicated to console/DebugLog. See the [vehicle trace guide](JavaPatches/README.md#vehicle-authority-recovery-and-diagnostic-logs) for errors and collection details. Install matching updated Toolkit/Java mods on every side first; that JAR update follows the normal restart/approval procedure.

## Update the set

1. Stop the server and all clients. Back up the world and `Zomboid/Lua/`, including Wishlist data, `QuartermasterPresets.txt`, `PZSTQuartermasterPresets_a.txt`, `PZSTQuartermasterPresets_b.txt` and `PZSTQuartermasterTagRules.txt` when present. Keep these files and both mods' existing settings; they preserve lists, sorting presets and preferences. Container designations stay in the world save.
2. Delete the old installed `Zomboid/mods/PZSurvivorWishlist` folder from every client, Host and dedicated-server installation. In the game's Mods menu, remove the old `PZSurvivorWishlist` Mod ID from each saved single-player profile's mod list; leave `PZSurvivorToolkit` enabled. Never load the old Wishlist folder and integrated Toolkit version together. Do not delete `Zomboid/Lua/PZSurvivorWishlist/` or the Wishlist Mod Options.
3. Update the repository and repeat preparation. Replace both owned local mod folders on the server and clients with this matching prepared version; do not merge old and new files. If an earlier prepared set supplied local CleanUI, NewMusic or `damnlib` overrides, remove those overrides so the Workshop copies load.
4. Copy only `Mods=` and `WorkshopItems=` from the prepared INI into an existing server profile. Disable the separate mods listed below in server and single-player profiles; Toolkit now includes their features. Keep saved preferences and data.
5. Keep third-party mods subscribed through Workshop. The prepared set updates only Toolkit and Java Patches. Reapprove changed Java JARs when prompted on clients and the server.
6. Start and join, checking the server Java loader as above. For version mismatches, compare both owned local folders and Workshop updates. Keep `DoLuaChecksum=true`.


If migrating from older versions, remove these separate copies:

| Separate mod to disable | Workshop ID | What to keep |
|---|---|---|
| Quartermaster | `3761216758` | Presets, container designations and options |
| ContainerCapacityIndicator | `3789660055` | Existing display preferences |
| BravoItemDetails | `3477237184` | Existing display and sorting preferences |
| HasResearch | `3567695139` | Existing indicator preferences |
| SeedSeasonIndicator | `3734639991` | Existing planting preferences |
| organizedCategories_core | `3370707195` | Existing Stick protection marks; Toolkit recognizes them |

Keep `MedicineMoodlesB42`, `TakeAnyAmount` and `TVRadioReinventedFix4220` disabled as well. Keep **Moodle Framework** and the main **TV & Radio ReInvented** mod enabled. Never run both a separate copy and its integrated Toolkit replacement.

## TV & Radio ReInvented

The INI includes the main `TVRadio_ReInvented` mod. Toolkit fixes device recognition on EN/RU clients and the native macOS video path; do not enable the separate `TVRadioReinventedFix4220`.

- **macOS:** install the complete TV mod, including `.bik` files in `42/media/videos/`. A matching Toolkit Java Patches build resolves requests from the active mod directory before native caching, so no separate `Project Zomboid.app/workshop` symlink is needed.
- **Linux/SteamOS:** the former external fix describes a `steamapps/common/workshop` link in its [path instructions](https://steamcommunity.com/sharedfiles/filedetails/?id=3796050675). Toolkit's automatic path fix targets macOS; playback on Linux/SteamOS and Windows/Proton was not verified in that scenario.

## Third-party setup and troubleshooting

- For dependency IDs, load order, controls and known caveats, use the [selected mod catalog](docs/MODPACK.md). The supplied INI already selects the required modules.
- **Winter, lights and Jeep:** the INI selects Immersive Snow (`3810071828`, `ImmersiveSnow`), JB's Bugs In Lights (`3717902500`, `JB_BugsInLights`), that DAMN Library (`3171167894`, `damnlib`) before the main Jeep (`3287727378`, `92jeepYJ`), and Furniture Push & Pull (`3781319724`, `FurniturePushPull`). Install these Workshop items on Host and clients. Optional `92jeepYJJP18` only enables Jurassic Park variant spawns and requires the main Jeep; it and Immersive Snow's Viewpoint addon remain disabled. The downloaded B42 metadata confirms that the main Jeep needs only `damnlib`. Existing sandbox settings are preserved; full-pack SP/Host behavior remains unverified.
- **Before moving valuable furniture**, check filled-container conservation and Quartermaster designations in a disposable save: recent mixed-mod reports describe disappearing crates despite an upstream B42.21 fix. See [Furniture Push & Pull](docs/MODPACK.md#61-furniture-push--pull).
- **New Music:** subscribe to Workshop `3739256725` on Host and clients and enable `NewMusic`. The INI keeps the base player and its Zomboid OST; no additional song packs are selected. Remove the unavailable ABBA Gold (`3784065691`, `NMBJABBA`), Queen (`3777937059`, `NMBJQ`) and Fleetwood Mac (`3751236222`, `NMBJFM`) entries from existing Host and single-player selections, keeping `NewMusic`. Back up existing saves first; media supplied by the removed packs will no longer be available. Toolkit disables NewMusic vanilla CD/player conversion and its associated inventory observer at runtime, even if an existing save enables conversion. Use the Workshop NewMusic copy; no separate NewMusic archive or local override is distributed. Base media/device loot and player volume preferences are preserved. See [playback and compatibility limits](docs/MODPACK.md#56-new-music); full-pack B42.21 SP/Host audio and TV & Radio ReInvented coexistence remain unverified.
- **Open Jackets:** subscribe to Workshop `2812326159` and enable both `SpnOpenClothBase` then `SpnOpenCloth`. **Climb Ladders:** subscribe to `3774776279` and enable `SubirEscaleras`. The supplied INI already includes all three Mod IDs. Fluffy Hair (open hoodies only) and Build Ladders (new construction recipes) are optional and not selected. See [clothing limits](docs/MODPACK.md#55-spongies-open-jackets) and [ladder controls/limits](docs/MODPACK.md#56-climb-ladders); full-pack SP/Host behavior remains unverified.
- **Before removing Nick's Turn Off Fridges, plug every fridge/freezer back in.** Its unplugged state persists on the appliance. [Details](docs/MODPACK.md#52-nicks-turn-off-fridges).
- **Before salvaging a whole vehicle**, empty its containers, remove occupants and animals, disconnect towing and uninstall wanted parts. [Vehicle Repair Overhaul limits](docs/MODPACK.md#54-vehicle-repair-overhaul).
- For stuck animals, preserve the save and collect client/server logs around one Grab attempt before deleting or replacing the animal. Check `animal=true`, `equipment=true`, `hutch=true` and their actual transformations in the [Java activation guide](JavaPatches/README.md#verify-activation). The selected Workshop timer fix is complementary; it does not restore lost animals.
