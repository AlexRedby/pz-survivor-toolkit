# Toolkit Java Patches (Experimental)

`PZToolkitJavaPatches` is an optional Java mod for Project Zomboid **B42.21 only**. It requires **ZombieBuddy 2.3.4 or newer** and is separate from PZ Survivor Toolkit. The generated mod is version **0.1.2**. It patches client zombie-speed decoding and vehicle interpolation recovery, plus server-side VHS restart handling. Each patch checks its target class bytecode and disables itself if the build is unsupported. It remains experimental: it is not established as a fix for minute-long vehicle freezes or every network movement jerk.

The VHS fix prevents an old stop timer from cancelling playback after a quick Stop/Play sequence. This engine problem is reproducible through TV & Radio ReInvented and the native cassette controls. Verification on a real B42.21 server and two EN/RU clients passed eight checks per client, including cassette dialogue, 62.5 XP each and normal completion. The Windows Host launcher below still needs testing on Windows.

## Build

The build machine needs Python 3 and **JDK 25 or newer**: JDK 21 cannot read this game build's classes. The game's bundled Java runtime is insufficient for compilation. Install ZombieBuddy on every client, including the Host owner, using the [one-time client setup](../MOD_INSTALL.md#zombiebuddy-one-time-client-setup).

For building, `ZombieBuddy.jar` must be in the same game Java directory as `projectzomboid.jar`. Run from the repository root; on Windows:

```powershell
py -3 JavaPatches/build.py --game "D:\SteamLibrary\steamapps\common\ProjectZomboid"
```

On macOS/Linux, use `python3 JavaPatches/build.py --game "/path/to/game/Java-directory"`. Replace each example path with your own. `--game` must point to the directory containing both JARs. The script finds the JDK through `JAVA_HOME`, the macOS JDK lookup, or `PATH`. If it chooses an older JDK, add `--jdk "C:\path\to\jdk-25"` (or the corresponding path on your platform).

The script reads game dependencies and writes output into `JavaPatches/build/`. Add `--check` to run the original-engine versus patched-engine vehicle interpolation and media restart regression checks; this command does not include a separate zombie-speed regression. Generated files are not committed to the repository.

## Install

1. With the game closed, copy the entire `JavaPatches/build/PZToolkitJavaPatches` folder into `%USERPROFILE%\Zomboid\mods` on Windows or `~/Zomboid/mods` on macOS/Linux. Distribute the same built folder to every player and to the Host/server if its profile enables this mod.
2. In each client's Mods menu, enable **ZombieBuddy**, then **Toolkit Java Patches (Experimental)**. Enable both in the selected Host/server profile as well. Approve the **PZToolkitJavaPatches** JAR when ZombieBuddy asks.
3. Keep this local mod out of `WorkshopItems=`: it has no Workshop ID. Its Mod ID is `PZToolkitJavaPatches`; the repository's default selected INI does not enable it.

## Server loader for VHS

Host starts a separate Java process; a client-side ZombieBuddy loader does not automatically load into it. The VHS patch must run on the server.

**Windows Host:** leave Steam running. Start the game from the repository root with the following command, using your game directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File JavaPatches/start-host.ps1 -Game "D:\Games\SteamLibrary\steamapps\common\ProjectZomboid"
```

Then open Host. `zbNative.dll` and `ZombieBuddy.jar` must already exist in that directory after ZombieBuddy setup. The script passes the loader to the launched game and its server without changing system-wide environment variables or the Steam process. It checks existing JSON loader settings to avoid loading the agent twice, and rejects an existing ZombieBuddy entry in `JDK_JAVA_OPTIONS`.

For a **dedicated server**, add `-javaagent:/full/path/ZombieBuddy.jar` to the JVM arguments before `zombie.network.GameServer`; on Windows use `-agentpath:"D:\path\zbNative.dll"`. Enable `ZombieBuddy;PZToolkitJavaPatches` in the server profile and grant the server loader permission for this JAR. Check the **server log** for `[PZToolkitJavaPatches] ... media=true`. Without that line, the server-side VHS fix has not loaded.
