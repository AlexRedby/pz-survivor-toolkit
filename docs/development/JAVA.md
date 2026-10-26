# Java patch development

[Development](../DEVELOPMENT.md)

Build and test the engine patches and test-only instrumentation. Run commands from the repository root. Loader installation is in the [Java user guide](../../JavaPatches/README.md).

- [Java development](#java-development)
- [Java patch boundaries](#java-patch-boundaries)
- [Test video](#test-video)

## Java development

Java Patches supports mixed Java/Kotlin sources. Use the [Kotlin 2.4.21 compiler distribution](https://github.com/JetBrains/kotlin/releases/tag/v2.4.21). Give the build its distribution root (the directory containing `lib/`, not `bin/`): `--kotlin-home` takes precedence over `KOTLIN_HOME`, which takes precedence over `kotlinc` on `PATH`. Both `JavaPatches/build.py` and `tools/prepare_install.py` accept `--kotlin-home`. The compiler and stdlib must both be version 2.4.21; the game-bundled Kotlin 1.4.10 and an arbitrary latest compiler do not satisfy this requirement. Builds do not download dependencies.

For a local macOS/Linux setup, set these paths once in the shell, replacing the placeholders with your JDK 25+, Kotlin 2.4.21 distribution root, and game Java directory (the one containing both `projectzomboid.jar` and `ZombieBuddy.jar`):

```sh
export JAVA_HOME="/path/to/jdk-25"
export KOTLIN_HOME="/path/to/kotlin-distribution"
export PZ_GAME="/path/to/game/Java"
export PATH="$JAVA_HOME/bin:$PATH"
python3 tools/prepare_install.py --game "$PZ_GAME" --jdk "$JAVA_HOME" --check
```

The explicit flags are shown so the selected JDK and game are clear; Kotlin is selected from `KOTLIN_HOME`. If the build reports a missing or invalid Kotlin distribution, check that `KOTLIN_HOME` points to the root containing `lib/kotlin-compiler.jar` and `lib/kotlin-stdlib.jar`, both report version 2.4.21, and the distribution includes its license files. Passing `--kotlin-home /path/to/kotlin-distribution` overrides the environment. Discovery through `PATH` requires an executable `bin/kotlinc` script; if an archive extractor removed its executable permission, use `KOTLIN_HOME` or unpack it with permissions preserved. Playing and launching Host do not require this compiler: the ordinary mod JAR bundles its relocated private runtime. The early font JAR remains Java-only. The distribution does not include `kotlin-reflect` or promise Kotlin reflection over relocated metadata.

Kotlin compiles against the Java sources before `javac` compiles the Java patch wrappers. Both target JVM 25, matching the supported B42.21 game runtime: Kotlin uses `-jvm-target 25` and Java uses `--release 25`. Regression classes, the build-only relocator, authoring helpers and native-fixture helpers use the same target. Project classes in the ordinary and early-font JARs have class-file major version 69; the bundled third-party Kotlin stdlib retains its upstream bytecode version. The native JVM checks exercise the actual ZombieBuddy 2.3.4 patch pipeline, including cold loading and writable advice, on Java 25. The ordinary JAR bundles the Kotlin stdlib under `net.alexredby.pztoolkitruntime.kotlin`, plus module metadata and license notices. A build-only ASM tool from the compiler distribution relocates application/runtime references, keeping the game's bundled Kotlin 1.4.10 separate. No compiler or relocation tool is shipped.

Runtime logic and its associated regression bodies use Kotlin. Prefer immutable locals, constructor properties, nullable types, named objects for shared services and value types for snapshots. Preserve native identity, numerical operation order, virtual getter dispatch, live collections, scratch storage and existing threading; per-frame paths should not allocate just to use collection operators. Patch annotations and static entry points can live on Kotlin objects with `@JvmStatic` and `@JvmField`; the crafting, fluid, item-stat, fence and vehicle-trace facades do so. Nine ordinary Java owners remain because their advice assigns back into annotated parameters, locals, results or throwables. Kotlin function parameters are immutable: introducing a local `var` or returning a replacement does not update the annotated JVM slot used by the current instrumentation API. Keep that small write-back adapter in Java rather than adding another bytecode generator or changing the instrumentation protocol. For example, `Main.TVVideoPath` delegates to `TVVideoPaths.kt` but assigns the advice argument in Java. Java is not required merely to preserve a class monitor; Kotlin static synchronized methods preserve that monitor too. `MainPolicy` evaluates each bytecode guard only when the corresponding Java compatibility field is initialized; it has no eager group of support flags. `MainSupport.startup()` keeps the original target-preparation order before ZombieBuddy patch registration. This avoids changing cold initialization through an incidental Kotlin object dependency.

The independent early font JAR intentionally retains `PreMain`, `FontPage` and `FontAssets` in Java. It may run before the ordinary mod or its private Kotlin runtime exists; calling Kotlin support here would break that loading contract. It contains only those bootstrap classes, has no ordinary-mod/runtime dependency and keeps its existing explicit activation and approval path. `--test FontColdChecks` exercises this isolated premain path, native glyph pixels and subsequent ordinary-mod loading. Its Java cold support must also remain usable before the ordinary JAR is appended. Ordinary font regression bodies can use Kotlin.

`--test TVVideoPathChecks` exercises the real woven game method. `--test KotlinRuntimeChecks` starts without the mod on the classpath, registers the built JAR through instrumentation and checks its private runtime alongside the unchanged game runtime. `CartBootstrapCheck.java` retains a runtime-independent entry point to test startup preparation and retransformation. These cold fixtures must not acquire Kotlin references before the operation under test.

`python3 JavaPatches/build.py` produces `JavaPatches/build/PZToolkitJavaPatches`; it accepts `--game` for the directory containing both game/loader JARs, `--jdk` for JDK 25+, and `--check` for native JVM regressions. The checks compare original and patched engine vehicle interpolation, vehicle ownership recovery (native collision race, validated driver/towing guards and idempotency), continuous opt-in vehicle tracing (runtime controls, rotation, sampling limits, Host authorization and I/O recovery), media restart, build cancellation/completion behavior, animal location/identity/capacity reconciliation, equipment acknowledgements, hutch unloading and native string-property startup fallback (cold loader entry, IDs, values, storage and unrelated diagnostics), plus native fluid-container token normalization, fence-validation timing and early font-page loading; cart checks cover movement budgets/collision, native cadence and stop/reverse transitions, grip/grounding and wheel rolling. There is no separate zombie-speed regression in this command. Generated output is ignored by Git.

For one JVM regression, use `python3 JavaPatches/build.py --test MediaChecks`; repeat `--test` to select more. When present, `--test` overrides the `--check`/`--check-video` groups; without it, those flags retain their existing behavior. `--help` lists the available test names. Each JVM regression has a 120-second timeout; change it with a positive integer `--test-timeout SECONDS`. A timed-out test fails and retains its output in the reported `JavaPatches/build/<check-name>.log`. The limit applies to each test invocation, not to compilation.

Migrate associated regression bodies to Kotlin with each runtime module. The builder selects either `.kt` or `.java`, resolves selected Kotlin helpers, and compiles Kotlin checks against the original application metadata with friend access for `internal` declarations. It relocates the resulting test bytecode before compiling remaining Java fixtures; executed tests use the distributed private runtime. Java fixtures remain appropriate for a demonstrated loader or instrumentation contract: `KotlinRuntimeChecks.java` must start without any Kotlin runtime reference before it appends the mod JAR. Do not add the compiler, unshaded stdlib or raw application classes to its runtime classpath.

Use the pinned [ktfmt 0.65 with-dependencies JAR](https://github.com/Kotlin/ktfmt/releases/download/v0.65/ktfmt-0.65-with-dependencies.jar) for the Kotlin-language profile (four-space indentation, 100-column wrapping and trailing commas), with `.editorconfig` for matching editor settings:

```sh
python3 tools/format_kotlin.py --formatter-jar /path/to/ktfmt-0.65-with-dependencies.jar --check
```

Omit `--check` to format; `KTFMT_JAR` can supply the JAR path and `--jdk` selects a JDK explicitly. The command validates the pinned SHA-256 and downloads nothing. It covers handwritten runtime and regression sources. The three generated numeric tables retain their generator-owned layout; use the existing curve/clearance/wheel regeneration checks instead of hand-formatting them. The formatter and its compiler dependencies are development tools and are not shipped with the mod.

The ordinary JAR contains portable source/build fingerprints in `META-INF/pztoolkit-build-inputs.json`. The metal-pickup retarget/replay, shopping-cart pickup and cart-locomotion generation tools verify these fingerprints before compiling helpers or writing output. Rebuild Java Patches after changing runtime sources or build tools; missing, legacy or stale artifacts fail with a rebuild instruction. These tools use the complete built Java/Kotlin runtime, including its private stdlib, rather than a local compiler at execution time. The separate Java-only clip checker does not need Kotlin. Direct Java-source overlays are no longer used.

## Java patch boundaries

### Equipment acknowledgements

Version 0.1.5 fixes the reproduced empty-hands symptom. Equip uses ordered channel 0 while AnimalCommand uses channel 1. If Equip arrives before RemoveAndGrab, its local inventory lookup fails and parsing returns before consuming the remaining hand status. The client previously acknowledged its empty/old hands, the server accepted that acknowledgement and sent an equipment update that removed the animal from the client's hands again. The exact animal item remained in both inventories.

The client now omits acknowledgements for incomplete local equipment parses. B42.21 gives each handler an exactly bounded packet buffer; both that framing and EquipPacket have bytecode guards. Fully parsed packets, remote players, server handling and intentional equipment changes retain vanilla behavior. The patch does not create items, change IDs or reorder network channels. An unresolved secondary-only item after a fully read packet is outside this fix; the demonstrated animal carry failure occurs on the primary item.

### Hutch unloading

The fingerprint-guarded hutch-unload hook temporarily supplies a non-null snapshot of the native `animalInside` map to `IsoHutch.removeFromWorld`, then restores the exact original map in a finally-style exit, including on exceptions. Native superclass cleanup, hutch-manager removal and every present animal's cleanup still run. Empty slots, stored counts, animal references and map identity remain unchanged after the call. It creates/deletes no animals, edits no saves and does not suppress unrelated exceptions. Valid-only maps use the original path without copying; custom map implementations and unsupported game bytecode retain native behavior.

## Test video

Install [Toolkit Java Patches](../../JavaPatches/README.md) in the isolated test profile and pass its own `-cachedir`, with `-novoip` and `voiceEnable=false`. No menu or automatic recording is added. ZombieBuddy exports these globals to client Lua:

```lua
assert(toolkitVideoStart("/absolute/path/to/test-profile/videos", "/absolute/path/to/ffmpeg"))
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

The native capture fixture currently covers macOS, English UI and single-player. Russian UI, multiplayer, Windows/Linux, live resize, sustained 4K and forced-shutdown recovery remain unverified. See the [video fixture guide](../../tests/native_queue/contributions/video-recording/README.md) for preparation, recording and decoding commands.
