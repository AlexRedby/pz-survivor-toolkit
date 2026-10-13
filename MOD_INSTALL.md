# Install the selected mod set

For the Steam edition of Project Zomboid **B42.21**. The server and all players must use the same game build and identical local mod files.

The [server INI](SurvivorQoL-selected.ini) selects **41 Mod IDs / 37 Workshop items**. All three repository mods are required: **PZ Survivor Toolkit v0.1.29**, **Survivor Wishlist v0.1.0** and **Toolkit Java Patches v0.1.2**. The Java component is experimental and targets B42.21 only. Feature switches remain per-player; the action queue is enabled on fresh profiles and preserves existing preferences. See [features and verification limits](README.md).

## Prepare once

The server owner prepares one copy for everyone. Players receiving it do not need Python or a JDK.

1. Clone or download [this repository](https://github.com/AlexRedby/pz-survivor-toolkit). Install **Python 3.10+** and **JDK 25+** on the build machine.
2. Install the [ZombieBuddy loader](#zombiebuddy-loader) there. The game Java directory must contain both `projectzomboid.jar` and `ZombieBuddy.jar`.
3. From the repository root run `python3 tools/prepare_install.py` on macOS/Linux, or `py -3 tools/prepare_install.py` on Windows. For a custom installation add `--game "/path/to/folder-containing-both-jars"`; to choose a JDK add `--jdk "/path/to/jdk-25"`. Add `--check` to run the native Java regression checks too.
4. Give every player the generated **dist/SurvivorQoL** folder. It contains `mods/PZSurvivorToolkit`, `mods/PZSurvivorWishlist`, `mods/PZToolkitJavaPatches`, `Server/SurvivorQoL-selected.ini` and the Windows/macOS Host launchers. It contains our mods only; Workshop supplies the rest. Generated output is ignored by Git, uncompressed, and safely replaced on the next successful preparation. Live game files and profiles are untouched.

## Local mods: server and every player

With the game/server stopped, copy the **three entire folders inside the prepared `mods` folder** into `Zomboid/mods`. Keep their `common` and `42` subfolders. Check that each has `42/mod.info`; avoid double nesting such as `PZSurvivorToolkit/PZSurvivorToolkit`.

| Platform | Zomboid directory |
|---|---|
| Windows | `%USERPROFILE%\Zomboid` |
| macOS / Linux | `~/Zomboid` |
| Dedicated server | `Zomboid` in the home directory of the account running the server; use the specified directory when launching with `-cachedir` |

These local mods have no Workshop items and **do not download when joining**. Distribute the same prepared folders to everyone. If switching a Workshop mod from a local copy to Steam downloads, move its old local folder out of `Zomboid/mods` so it does not override the download.

## Server

1. Stop the server. Back up the world and an existing profile's INI. Include `Zomboid/Lua/PZSurvivorWishlist/` in backups: shared lists are stored there separately from the world, under its encoded save path. Keep that save path when restoring.
2. Install all three [local mod folders](#local-mods-server-and-every-player).
3. For a **new profile**, copy the prepared `Server/SurvivorQoL-selected.ini` into `Zomboid/Server`. For an **existing profile**, copy only the `Mods=` and `WorkshopItems=` lines into its existing INI; keep its other settings.
4. Keep the supplied order. ZombieBuddy comes first, Java Patches immediately after it, libraries before their dependants, Toolkit before CCI/MP Fast Forward/Better Containers, Realistic Dashboard before Navigator, Wishlist after the crafting/UI mods, and `organizedCategories_core` last. All local IDs are already included; do not add them to `WorkshopItems=`.
5. Set up the [server Java loader](JavaPatches/README.md#server-loader). **Host owners must complete the client steps too**, then launch through the supplied Host launcher. Dedicated servers also need the loader for the VHS fix.
6. Choose `SurvivorQoL-selected` in **Host**, or start the dedicated server with `-servername SurvivorQoL-selected`. Use your existing profile name if you updated it. The Steam server downloads `WorkshopItems=` automatically; separate subscriptions or SteamCMD Workshop downloads are unnecessary. Approve the local Java JAR for the server and check its loader log as described in the Java guide.

The INI does not transfer sandbox settings or keybindings. When moving an existing world, also copy `<profile-name>_SandboxVars.lua` under the same profile name. The supplied INI sets `SleepAllowed=true` and `SleepNeeded=false`. When copying only the mod lists, change sleep settings separately if wanted.

## Client

1. Close the game. Subscribe to [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) and wait for Steam to download it, then complete the [one-time loader setup](#zombiebuddy-loader).
2. Install the same three prepared [local mod folders](#local-mods-server-and-every-player) used by the server.
3. Start the game and join. Select **Install** at the Workshop prompt: the game downloads the remaining required items and enables the server's mods in its order. Approve **PeekAView** and **PZToolkitJavaPatches** when ZombieBuddy asks; save the decisions. The same JARs may need approval again after an update.
4. Configure features under **Options > Mods > PZ Survivor Toolkit** and **Survivor Wishlist**. The action queue and prerequisite-crafting planner are optional and enabled on fresh profiles; TV and Navigator switches appear with their respective mods. Settings are local to each player and apply without restarting.
5. Set shortcuts: Toolkit highlight **F8**, Wishlist **K**, Peek a View **F9**, Better Containers Proximity Lock **F10**, Proximity Toggle **F11**, Corpse Only **F12**. Keep MP Fast Forward on **Numpad 0-4**. Disable Better Containers **Advanced Display Categories** because organizedCategories supplies them. Enable **Nested Containers Player/Loot**, keeping its multiplayer restrictions. Each player applies these preferences; the INI does not distribute them.

## ZombieBuddy loader

Install **ZombieBuddy 2.3.4+** on every client and in the server process. A Workshop subscription alone does not install the loader.

- **Windows client/Host:** use the official [ZombieBuddyInstaller.exe](https://github.com/zed-0xff/ZombieBuddy/releases/tag/windows_installer), select **Install or update ZombieBuddy**, then **Both** for normal and alternate launches. Review and apply its changes.
- **macOS / Linux client:** copy `ZombieBuddy.jar` from `steamapps/workshop/content/108600/3619862853/mods/ZombieBuddy/libs/` into the game Java directory. On macOS this is `Project Zomboid.app/Contents/Java/`; on Linux it is usually `ProjectZomboid/projectzomboid/`. Add `-javaagent:ZombieBuddy.jar --` to the game's Steam launch options. The final two hyphens are required. Follow the [author's installation guide](https://github.com/zed-0xff/ZombieBuddy/blob/master/doc/Installation.md) for launch variants.
- **Host:** leave Steam running and use the prepared `start-host.ps1` on Windows or `start-host.command` on macOS, following [these commands](JavaPatches/README.md#server-loader). They also pass the loader to Host's separate server process. A regular client-only Steam launch does not guarantee this.
- **Dedicated server:** follow the [server JVM and approval steps](JavaPatches/README.md#server-loader). Check the server log as well as the client log.

After launching the client, check for **ZombieBuddy ... loaded** in the upper-left corner. Java approval is per machine/account and JAR content; distribute the built mod folders, not another person's approval file.

## Use the shared wishlist

1. Press **K** or the sidebar **List** button. Add items from the searchable catalog, inventory context menu or crafting controls; no owned sample or recipe is required.
2. Under **Sharing**, grant editing to named server usernames, your faction, or both. Everyone with access edits the same list; only its owner changes access.
3. Set desired quantities and mark goals completed manually. **Carried by you** counts your own inventory and bags, not the team's supplies. Configure row highlights, visible ground-item highlights, crafting controls, colour and shortcut under **Options > Mods > Survivor Wishlist**.

Wishlist highlights wanted item rows in opened inventories and visible loose items; it does not reveal container contents. It needs neither Shopping List nor WANTED. See [features and limits](README.md#survivor-wishlist).

## Update the set

1. Stop the server and all clients. Back up the world, Wishlist's data directory and old local mods outside `Zomboid/mods`.
2. Update the repository and run `tools/prepare_install.py` again. Replace all three local folders on the server and clients with this matching prepared version; do not merge old and new files.
3. Copy only `Mods=` and `WorkshopItems=` from the prepared INI into an existing profile. Keep `MedicineMoodlesB42`, `TakeAnyAmount` and `TVRadioReinventedFix4220` disabled; Toolkit supplies their replacements. Keep Moodle Framework and the main TV & Radio ReInvented mod.
4. Use one installation method per Workshop mod: Steam or a complete local copy. The INI does not update local copies. Reapprove changed Java JARs when prompted on clients and the server.
5. Start and join, checking the server Java loader as above. For version mismatches, compare all three local folders and Workshop updates. Keep `DoLuaChecksum=true`.

## TV & Radio ReInvented

The INI includes the main `TVRadio_ReInvented` mod. Toolkit fixes device recognition on EN/RU clients and the native macOS video path; do not enable the separate `TVRadioReinventedFix4220`.

1. Click the empty VHS slot and choose a tape from your inventory, bag or a reachable nearby container, or drag a tape onto the slot. Press Play to start it. Clicking the inserted tape ejects it directly. Fully watched tapes for the current character have the inventory checkmark; unfinished tapes are unmarked and appear first. Disable **Improve VHS controls** under **Options > Mods > PZ Survivor Toolkit** to restore the original menu. Inventory and outside clicks keep the window open; use its X button to close it. **Keep TV/radio windows open** controls that behavior separately. Both settings are per-player and appear only while TV & Radio ReInvented is active.
2. On native macOS, Toolkit resolves video files from the active TV mod's actual directory. A separate `Project Zomboid.app/workshop` symlink is unnecessary. Install the complete TV mod, including `.bik` files in `42/media/videos/`; either a full local copy or Workshop installation works. Lua files alone are insufficient.
3. On native Linux/SteamOS, the previous external fix recommended linking `steamapps/common/workshop` to `steamapps/workshop`; see its [path instructions](https://steamcommunity.com/sharedfiles/filedetails/?id=3796050675). Toolkit's automatic video-path fix targets macOS. Linux/SteamOS and Windows/Proton video playback were not verified in that scenario.

## Nested bags in multiplayer

Carried bags and ordinary bags on the ground are supported. To access a bag inside a crate, first take the whole bag into your inventory, open it, then put it back. Removing Better Containers' restriction does not fix the network address of such nested containers; the protection remains enabled.
