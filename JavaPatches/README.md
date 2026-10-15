# Toolkit Java Patches (Experimental)

`PZToolkitJavaPatches` v0.1.4 is an independent Java mod for **B42.21 only**, required in our selected set. It needs **ZombieBuddy 2.3.4+** in every client and the server process. It patches client zombie-speed decoding, vehicle interpolation recovery and animal trailer membership, plus server-side VHS restart handling and build cancellation acknowledgements. Each patch checks its target class bytecode and disables itself on an unsupported build. It remains experimental: it is not established as a fix for minute-long vehicle freezes or every movement jerk.

## Prepare and install

The server owner prepares the whole set once; other players need neither Python nor a JDK. Follow the [combined installation guide](../MOD_INSTALL.md). From the repository root:

```sh
python3 tools/prepare_install.py --check
```

On Windows use `py -3` instead of `python3`. The build machine needs **Python 3.10+**, **JDK 25+**, and a B42.21 game Java directory containing both `projectzomboid.jar` and `ZombieBuddy.jar`. The game's bundled runtime cannot compile the patch. For custom locations:

```powershell
py -3 tools/prepare_install.py --game "D:\SteamLibrary\steamapps\common\ProjectZomboid" --jdk "C:\path\to\jdk-25" --check
```

Use corresponding paths on macOS/Linux; `--game` points to the folder containing both JARs, and `--jdk` to the JDK home. Without these options, the builder uses standard Steam locations and finds the JDK through `JAVA_HOME`, the macOS JDK lookup or `PATH`.

Copy the three folders inside `dist/SurvivorQoL/mods` to `Zomboid/mods` on the server and every client. The prepared INI already includes `ZombieBuddy;PZToolkitJavaPatches` first, followed by the rest of the selected set. This local patch has no Workshop ID. Approve its JAR in ZombieBuddy on each client and server; see Host's saved-approval step below.

For Java-only development, `python3 JavaPatches/build.py` produces `JavaPatches/build/PZToolkitJavaPatches`; it accepts the same `--game`, `--jdk` and `--check` options. The checks compare original and patched engine vehicle interpolation, media restart, build cancellation/completion behavior and animal location/identity/capacity reconciliation; there is no separate zombie-speed regression in this command. Generated output is ignored by Git.

## Programmatic test video (B42.21 client)

Install this Java mod in the isolated test profile and pass its own `-cachedir`, with `-novoip` and `voiceEnable=false`. No menu or automatic recording is added. ZombieBuddy exports these globals to client Lua:

```lua
assert(toolkitVideoStart("/private/tmp/my-pz-test/videos", "/opt/homebrew/bin/ffmpeg"))
-- Run the animation or test segment.
assert(toolkitVideoStop())
-- Poll on subsequent ticks; stop returns immediately while FFmpeg finalizes MP4.
local video = toolkitVideoStatus()
if video.state == "completed" then print(video.file, video.frames, video.seconds) end
if video.state == "failed" then error(video.error .. " | " .. video.log) end
```

Use an absolute output subdirectory inside the current profile's cache directory; symlink escapes are rejected. Each capture gets a unique filename and a sibling `.ffmpeg.log`; existing files are never overwritten. Pass an absolute executable path to an installed FFmpeg with `libx264`. Java tests may call the same static `VideoRecording.start(directory, ffmpeg)`, `stop()` and `status()` methods in `net.alexredby.pztoolkitjavapatches`.

`start()` returns whether the request was accepted, not encoder readiness. A second start during `starting`, `recording` or `stopping` returns false without replacing the active session. `stop()` accepts only the first stop request. Status states are `idle`, `starting`, `recording`, `stopping`, `completed`, `failed`; fields include `file`, `log`, `error`, `width`, `height`, `fps`, `frames`, `captured`, `dropped`, and `seconds` (encoded duration). Inspect `completed` before reading the finalized file or starting another capture.

The fixed profile is silent H.264 MP4, 30 FPS, CRF 18, `veryfast`, yuv420p. It captures the displayed game framebuffer including UI, without desktop windows. Actual GLFW framebuffer dimensions are used (including Retina), up to 4K / 8,294,400 pixels and 4096 pixels on either axis. Odd dimensions are padded by one pixel for H.264. Resize ends the capture with `failed` and finalizes already captured frames. A minimized window can supply no new images.

Capture uses one direct RGBA buffer plus three bounded heap buffers (at most about 127 MiB at 4K). GL readback and one copy happen on the render thread; encoding and pipe writes happen on a separate daemon thread. Slow rendering or encoding holds the previous image over missing frame slots, preserving wall time to within one 30 FPS frame, rather than speeding up the clip. The final frame is held until the stop timestamp. `dropped` counts capture opportunities skipped because no buffer was free; it does not count every duplicated output frame. This is test instrumentation, and synchronous GL readback can reduce game FPS.

After stop, a 15-second watchdog aborts an encoder that cannot finish. Normal JVM exit attempts a four-second flush; force-kill, encoder failure or a full disk can leave an incomplete MP4. There is no audio input, codec implementation or permanent recorder. The Display hook retains the per-class B42.21 fingerprint guard.

Run `python3 JavaPatches/build.py --check-video` with `PZ_TEST_FFMPEG` set to the FFmpeg executable (otherwise found on `PATH`; sibling `ffprobe` is required). This checks timing boundaries, delayed/gapped captures, last-frame hold, decoded colors, exact duration/dimensions, stop without frames and encoder failure. Ordinary `--check` retains its existing engine regressions.

Verified on macOS B42.21 on 15 October 2026 in a fresh isolated Sandbox profile: two consecutive Lua start/stop cycles each produced 1728x1020 H.264, 106 frames / 3.533333 seconds for measured 3.515-3.516 second intervals, with 106 captured and zero dropped frames. Full FFmpeg decode, three extracted frames and FFplay playback passed. A second active start, repeated stop and output outside the profile were rejected. The native fixture verified VOIP disabled. Resize and buffer-exhaustion guards were checked headlessly; live resize, 4K sustained load, Windows/Linux and force-kill recovery were not exercised.

## Server loader

Host starts a separate Java process. Loading ZombieBuddy only in the client does not guarantee the server VHS patch is active.

### Host: save approvals first

1. Complete the [client loader setup](../MOD_INSTALL.md#zombiebuddy-loader) and install all three prepared local mod folders. Subscribe to [Peek a View](https://steamcommunity.com/workshop/filedetails/?id=3710281407) as well as ZombieBuddy so both Java mods are available before the first Host launch.
2. In the client's **Mods** menu enable **ZombieBuddy**, **Peek a View** and **Toolkit Java Patches (Experimental)**. Restart when asked, then approve **PeekAView** and **PZToolkitJavaPatches**, choosing to **save each decision**. Do this before opening Host, and repeat when a changed JAR prompts again.
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
3. Run the first start interactively under the **account that will run the server**. ZombieBuddy's dedicated-server default uses console prompts: answer `y` to allow the **PZToolkitJavaPatches** JAR, then `y` to save. Review any other selected Java mod prompts too. Start it as a service only after approvals are saved; repeat interactively when a changed JAR needs approval.
4. Check the server log before using it for play.

### Verify activation

Client and server logs should contain `[PZToolkitJavaPatches] Experimental B42.21 patch: zombie=true, vehicle=true, media=true, build=true, video=true, animal=true`. This confirms matching game bytecode. Also check ZombieBuddy's actual transformation messages:

- Server: `[ZB] Transformed: zombie.radio.devices.DeviceData` and `[ZB] Transformed: zombie.core.BuildAction`.
- Each client: `[ZB] Transformed: zombie.characters.NetworkZombieAI`, `[ZB] Transformed: zombie.vehicles.VehicleInterpolation` and `[ZB] Transformed: zombie.characters.NetworkPlayerAI`.

These appear at the default log verbosity. Missing output, `false` values, or target-class/transformation errors mean setup is incomplete or needs investigation. The client also shows **ZombieBuddy ... loaded** in the upper-left corner. A client message alone does not confirm server activation.

The build acknowledgement patch lets Toolkit 0.1.30 interrupt active multiplayer construction safely. It reports the native server outcome over the same ordered channel as build transactions. Only confirmed cancellations may resume; completed builds never replay. An unsupported or unpatched server retains the queue restriction, and a missing terminal reply clears the waiting queue after 30 seconds.

## Animal trailer reconciliation

Version 0.1.4 reconciles an animal's client trailer membership when the server reports its world, hutch or inventory location. A late trailer snapshot could previously re-add an unloaded animal permanently, leaving an entry that cannot be grabbed. Cleanup removes duplicate references to the same animal, preserves its identity and recomputes occupied trailer capacity. No animals or inventory items are created or deleted.

`PZToolkitJavaPatches` is already in the selected INI; no additional Workshop item is needed. Install the updated prepared Java folder on the server and every client, including the host player, save the new JAR approval and restart the server and clients. Check `animal=true` and the actual `zombie.characters.NetworkPlayerAI` transformation in every client log. See [the combined guide](../MOD_INSTALL.md#animal-trailer-fix).

The 0.1.4 native-object regression checks world/hutch/item locations, duplicate membership, identity, capacity, repeat snapshots and client/server guards. An isolated B42.21 macOS dedicated-server/client test with the 27 selected local mods passed two hen grabs and the last live chick grab, followed by all three native drops alive with exact identities and trailer counts 2/1/0 on both sides. A test-only late-packet replay demonstrated the vanilla ghost and its repair through the actual woven decoder; that probe is excluded from the mod. The affected hosted save, Windows/Linux, WAN and UI clicking/pathfinding were not tested, and previously lost animals are not restored.

## Verification limits

The build patch passed native Java cancellation/completion race checks and an isolated B42.21 server run with two EN/RU clients. Each client passed 22 checks covering interruption and once-only resumption of wooden/metal barricades and a crate; the server verified exact material consumption. Real WAN races, split-screen and other platforms were not exercised.

The VHS patch cancels the old stop timer on a quick Stop/Play sequence. A native B42.21 server and two EN/RU clients passed eight playback checks each, including dialogue, 62.5 XP each and normal completion.

The complete prepared 41-Mod-ID set passed a separate B42.21 macOS dedicated-server smoke on 12 October 2026: 33 wishlist/UI/shared-editing checks per client, with Lua checksums enabled. Server media and client zombie/vehicle class transformations were verified, alongside the native build regressions. The macOS launcher's argument handling, duplicate-loader refusal and environment inheritance have automated tests. The user confirmed ordinary Host verification on 13 October 2026 and subsequently reported no observed issues in use, closing the longer-session follow-up. They attributed the reported combat/grapple jerks to a poor internet connection and closed that investigation. These reports are separate from the automated dedicated-server coverage above; Linux and mixed patched/unpatched clients have not been independently verified.
