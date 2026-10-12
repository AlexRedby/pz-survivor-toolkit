# Install the selected mod set

For the Steam edition of Project Zomboid B42.21. The server and all players must use the same game build and identical local mod versions.

The checked-in [server INI](SurvivorQoL-selected.ini) selects **39 Mod IDs / 37 Workshop items**, including local **Toolkit v0.1.21**. It excludes `MedicineMoodlesB42`, `TakeAnyAmount` and `TVRadioReinventedFix4220`; Toolkit supplies their replacement features. Keep Moodle Framework and the main TV & Radio ReInvented mod. **Survivor Wishlist v0.1.0** and **Toolkit Java Patches v0.1.2** are separate optional local mods, not enabled by that INI. See [README](README.md) for features and verification limits.

## Server

1. Stop the server. Back up an existing server's INI before changing it.
2. Download [SurvivorQoL-selected.ini](SurvivorQoL-selected.ini). For a new profile, put it in `Zomboid/Server`. For an existing profile, copy only its `Mods=` and `WorkshopItems=` lines into your profile's INI.
3. Preserve the `Mods=` order: **ZombieBuddy first**, libraries before dependent mods, base Neat mods before their XP add-ons, Eat Smart before Drink Smart, Moodle Framework and CleanUI before Toolkit, Toolkit before Container Capacity Indicator, MP Fast Forward and Better Containers, and Realistic Dashboard before Navigator. Load `organizedCategories_core` last. The supplied INI already has this order, Neat Building UI Only and Eat Smart Integrated.
4. Install the local Toolkit folder using the steps below. Give every player the same version.
5. Start the profile: choose `SurvivorQoL-selected` in **Host**, or start a dedicated server with `-servername SurvivorQoL-selected`. Use your existing profile name if you updated it. The server downloads the Workshop items listed in `WorkshopItems=`; you do not need to subscribe to each one manually.

For Peek a View, a dedicated server does not need the ZombieBuddy Java loader: keep both mods in the INI and install the loader on clients. **The Host owner must also complete every client step.** See the [Peek a View author's instructions](https://steamcommunity.com/workshop/filedetails/?id=3710281407). The optional Java VHS fix has a separate server-loader requirement, described below.

The INI does not transfer sandbox settings or keybindings. To move existing sandbox settings, also copy `<profile-name>_SandboxVars.lua` using the same profile name. The supplied INI sets `SleepAllowed=true` and `SleepNeeded=false`: sleep is allowed but not required. When copying only the mod lists, change sleep settings separately if you want them.

## Client

1. Close the game. Subscribe to [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) first and wait for Steam to download it; its files are needed for the separate loader setup.
2. Complete the one-time ZombieBuddy setup below.
3. Install the same local Toolkit folder used by the server.
4. Start the game and join the server. Select **Install** at the Workshop prompt: the game downloads the required set and enables the server's mods. You do not need to subscribe to the remaining mods individually or set their load order yourself. When ZombieBuddy asks to load the **PeekAView** JAR, approve it; you can save that decision.
5. Open **Options > Mods > PZ Survivor Toolkit** to configure individual features. This includes ground highlights, inventory filters, quantity transfers, bulk actions, vehicle-part removal to the ground, context-menu grouping and the action queue. TV and Navigator settings appear only with their respective mods. Medicine indicators require Moodle Framework; two grouped switches control the six medicine indicators and the two herb indicators. The old Medicine Moodles and Take Any Amount mods suppress Toolkit's corresponding replacements to avoid duplicates. Settings are local to each player and apply without restarting.
6. Set the selected-set shortcuts: Toolkit highlight **F8**, Peek a View **F9**, Better Containers Proximity Lock **F10**, Proximity Toggle **F11**, Corpse Only **F12**. Keep MP Fast Forward on **Numpad 0-4**. Disable Better Containers **Advanced Display Categories** because organizedCategories supplies categories. Enable **Nested Containers Player/Loot**, keeping its multiplayer restrictions. Each player applies these settings locally; the INI does not distribute them.

## ZombieBuddy: one-time client setup

- **Windows:** download the official [ZombieBuddyInstaller.exe](https://github.com/zed-0xff/ZombieBuddy/releases/tag/windows_installer), choose **Install or update ZombieBuddy**, then **Both** for normal and alternate launches. Review and apply the proposed changes.
- **macOS / Linux:** copy `ZombieBuddy.jar` from `steamapps/workshop/content/108600/3619862853/mods/ZombieBuddy/libs/` into the game's Java directory. On macOS this is `Project Zomboid.app/Contents/Java/` inside the game installation; on Linux it is usually `ProjectZomboid/projectzomboid/`. Open the game's Steam properties and add `-javaagent:ZombieBuddy.jar --` to the launch options. The final two hyphens are required. See the [author's installation guide](https://github.com/zed-0xff/ZombieBuddy/blob/master/doc/Installation.md) for exact paths and launch variants.

After launching, check for **ZombieBuddy ... loaded** in the upper-left corner. A Workshop subscription alone does not install the loader.

## Local Toolkit: server and every player

1. Clone or download the [repository](https://github.com/AlexRedby/pz-survivor-toolkit). Use the same `PZSurvivorToolkit` folder version for everyone.
2. With the game closed, copy the **entire PZSurvivorToolkit folder** into `Zomboid/mods`. Keep the `common` and `42` subfolders. Avoid double nesting such as `PZSurvivorToolkit/PZSurvivorToolkit`.
3. Verify that `Zomboid/mods/PZSurvivorToolkit/42/mod.info` exists. Mod ID `PZSurvivorToolkit` is already enabled in the supplied server INI.

| Platform | Zomboid directory |
|---|---|
| Windows | `%USERPROFILE%\Zomboid` |
| macOS / Linux | `~/Zomboid` |
| Dedicated server | `Zomboid` in the home directory of the account running the server; use the specified directory when launching with `-cachedir` |

Toolkit has no Workshop item and does not download automatically when joining. Replace its entire local folder with the game closed, using identical files on the server and clients. If switching **Workshop mods** from local copies to Steam downloads, move their old local folders out of `Zomboid/mods` so they do not override the downloaded versions.

## Optional Survivor Wishlist

1. With the game and server stopped, copy the repository's **PZSurvivorWishlist** folder into `Zomboid/mods` on the server and every client, preserving `common` and `42`.
2. Add `PZSurvivorWishlist` to the server's `Mods=` after the crafting/UI mods and before the final `organizedCategories_core` entry. It has no Workshop ID; do not add it to `WorkshopItems=`. For single-player, enable **Survivor Wishlist** in Mods for the save.
3. Open it with **K** or the sidebar **List** button. Add items from the searchable catalog, inventory context menu or crafting controls. Under **Sharing**, grant editing to named server usernames, your faction, or both. Every authorized member edits the same list; only its owner changes access.
4. Set desired quantities and mark goals completed manually. **Carried by you** counts your own inventory and bags, not the whole team's supplies. Configure row highlights, visible ground-item highlights, crafting controls, colour and shortcut under **Options > Mods > Survivor Wishlist**.
5. Back up `Zomboid/Lua/PZSurvivorWishlist/` together with the world. Lists are stored separately from the world under an encoded save path; preserve that save path when restoring the backup.

Wishlist is independent of Toolkit and does not need Shopping List or WANTED. It highlights wanted item rows in opened inventories and visible loose items on the ground; it does not reveal container contents. See [Wishlist features and test limits](README.md#survivor-wishlist).

## Update the set

1. Stop the server and close all clients. Back up the world and the local mod folders being replaced outside `Zomboid/mods`. Include Wishlist's separate data directory if you use it.
2. Update `Mods=` and `WorkshopItems=` from the supplied INI, then reapply any deliberately enabled optional local mods. Keep `MedicineMoodlesB42`, `TakeAnyAmount` and `TVRadioReinventedFix4220` disabled; Toolkit has replaced their required features since v0.1.20. Their Workshop files may remain on disk. Replace the whole Toolkit folder on the server and clients with one matching repository version. Its version is in `42/mod.info` under `modversion=`.
3. Use one installation method per Workshop mod: Steam or a complete local copy. For local installation, distribute identical updated folders to the server and clients; the INI does not update those copies.
4. Start the server and join with the clients. For version mismatches, compare local mod folders and Workshop updates; keep `DoLuaChecksum=true`.

## Optional experimental Toolkit Java Patches

The [JavaPatches guide](JavaPatches/README.md) covers building, ZombieBuddy setup, Host activation and loader verification. Install and enable this mod separately from Toolkit. It is not in the selected INI. All participants need the same built mod folder. This experimental patch has not been established as a fix for long vehicle desynchronization.

Mod ID: `PZToolkitJavaPatches`. For the VHS restart fix, the loader must also run in the **server process**; client-only ZombieBuddy setup is insufficient.

## TV & Radio ReInvented

The INI includes the main `TVRadio_ReInvented` mod. Toolkit fixes device recognition on EN/RU clients and the native macOS video path; do not enable the separate `TVRadioReinventedFix4220`.

1. Click the empty VHS slot and choose a tape from your inventory, bag or a reachable nearby container, or drag a tape onto the slot. Press Play to start it. Clicking the inserted tape ejects it directly. Fully watched tapes for the current character have the inventory checkmark; unfinished tapes are unmarked and appear first. Disable **Improve VHS controls** under **Options > Mods > PZ Survivor Toolkit** to restore the original menu. Inventory and outside clicks keep the window open; use its X button to close it. **Keep TV/radio windows open** controls that behavior separately. Both settings are per-player and appear only while TV & Radio ReInvented is active.
2. On native macOS, Toolkit resolves video files from the active TV mod's actual directory. A separate `Project Zomboid.app/workshop` symlink is unnecessary. Install the complete TV mod, including `.bik` files in `42/media/videos/`; either a full local copy or Workshop installation works. Lua files alone are insufficient.
3. On native Linux/SteamOS, the previous external fix recommended linking `steamapps/common/workshop` to `steamapps/workshop`; see its [path instructions](https://steamcommunity.com/sharedfiles/filedetails/?id=3796050675). Toolkit's automatic video-path fix targets macOS. Linux/SteamOS and Windows/Proton video playback were not verified in that scenario.

## Nested bags in multiplayer

Carried bags and ordinary bags on the ground are supported. To access a bag inside a crate, first take the whole bag into your inventory, open it, then put it back. Removing Better Containers' restriction does not fix the network address of such nested containers; the protection remains enabled.
