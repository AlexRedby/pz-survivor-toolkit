# Wooden cart motion fixture intake

Source-only contribution for a future native queue adapter. It is **not connected to a runner** and has **not been run live after parameterization**. `self_check.py` checks the manifest, files, Lua parsing and optional Java compilation. It never starts Project Zomboid.

The Java fixture supplies native keyboard input (`drive`, `gait`) and reads the current cart bank, root-speed ramp and animation tracks. `bootstrap.lua` equips carts, creates its HUD and prepares the disposable floor. `scenario-clips.lua` records 16 cases: two sexes, empty/full cargo, and comparison/direct Sprint/gait transitions plus a Run-stop control. The full 12-second records include turns, stops and returns to walking. It samples every 100 ms.

## Parameters and adapter boundary

Supply absolute paths in `PZ_CART_RUNTIME_FILE` (Lua file used by `cartLabReload`) and `PZ_CART_COMMAND_FILE` (optional command channel file). Both environment variables are mandatory. The file itself may be absent until a command is submitted. `cartLabPoll` accepts only `reload` and `screenshot`; write commands atomically. Loading/polling is adapter-owned, not installed by this contribution.

Before loading `test-area.lua`, provide this global, using values owned by the runner:

```lua
CartMotionConfig = {
    disposable = true,
    videoRoot = assert(RUN_VIDEO_ROOT),
    ffmpeg = assert(RUN_FFMPEG),
    area = {
        x=10825.5, y=10142.5, z=7,
        minX=10777, minY=10094, size=96, margin=2,
        floorSprite='carpentry_02_57',
    },
}
```

The coordinates are the original B42.21 calibration, not portable world discovery. The adapter must establish that the whole configured ground footprint is loaded. Required fields have no hidden path/profile defaults. The area accepts finite grid parameters and a bounded size up to 96; it retains the original object/floor/actor/collision validation and refuses any world other than single-player `CartTestArea`.

Create a **fresh, owned, disposable profile** with the manifest options/sandbox settings. Do not reuse a player save, delete an existing save automatically, or copy an old investigation profile. The fixture changes test inventory, clothing, Sprinting skill and floor tiles. It validates the complete footprint before creating floors and never clears unexpected objects.

Compile `Main.java` against local B42.21 `projectzomboid.jar` and `ZombieBuddy.jar` with JDK 25+ and `--release 17`. Package it as a test-only `CartLab` mod exposing `net.alexredby.cartlab`; approve the exact JAR hash in the isolated ZombieBuddy config. The manifest records the original JVM/game arguments as adapter templates, not an executable launch command. Supply the platform runtime/native libraries and exactly one ZombieBuddy agent with `policy=deny-new`. The macOS first-thread flag is platform-specific.

The live fixture requires Toolkit >=0.1.57 and JavaPatches >=0.1.14 **with the current candidate B42.21 cart-motion changes integrated**. Version numbers alone are insufficient: `cartLabRamp` reflects `State.pace`, `sprintMomentum`, `load` and calls `CartLegPace.targetSpeed`. These APIs are absent from the current main queue checkout. This contribution does not include or integrate those production changes. A missing reflected member must remain an exception that stops the record, never an empty diagnostic or PASS.

The adapter must own the exclusive native queue lock, existing-process checks, profile preparation, mod installation/approvals, launcher, probe agents, analyzers and cleanup. None is implemented here. Load the config, test area and bootstrap; wait for `BOOTSTRAP_READY`; then load the scenario. Missing bridges/configuration fail before the scenario changes the player. Bootstrap also checks the disposable world before equipping anything.

The fixture is single-player only. The legacy profile used RU (`options.ini`); other locales and MP have not been validated. Case IDs/log markers are stable ASCII strings and do not establish localization coverage.

## Checks and evidence

```sh
python3 tests/native_queue/contributions/wooden_cart_motion/self_check.py
python3 tests/native_queue/contributions/wooden_cart_motion/self_check.py \
  --game-java-dir "$PZ_GAME_JAVA_DIR" --jdk "$JAVA_HOME"
```

Lua syntax requires `luajit` or `lua` on PATH, or `--lua`. Java compilation requires both explicit dependency paths; omitted checks are reported as skipped. Compilation output goes to a temporary directory. There are no runtime binaries, saves, screenshots, videos, copied mods or game assets in this contribution.

Keep `[WOOD_BANK]` markers stable for existing analyzers. A complete record needs 16 unique `COMPLETE` markers after the latest `RUN_STARTED`, valid per-case windows and `ALL_COMPLETE cases=16`. Check `FAIL` and rejected video starts/stops. The manifest criteria additionally require grip, actual mesh, floor and original hip/leg/arm probes. Their source, dependencies, build commands, offline checks and limits are preserved in [evidence/README.md](evidence/README.md). The common-runner attachment/analysis adapter is still pending; missing instrumentation means **not verified**, not PASS.

## Known traps and limits

- The 32/64-tile pads were too small for the recorded path; 96x96 worked in the legacy stand. A larger pad can have far corners streamed out after a reset. Per-tick checks validate the current tile; before each record the scenario waits 1.8 seconds, then retries the **full** pad check for up to 6 seconds. An unloaded square still aborts; do not bypass it.
- Synthetic input patches both `GameKeyboard.isKeyDown` and `isKeyDownRaw`. `drive=-1` releases the override; `drive=0` is neutral input. Logical key bindings are used, not OS keyboard events. Runtime/profile options must disable toggle/double-tap Run/Sprint.
- Sprint requires controlled skill 10. The `runstop` control deliberately has skill 0 and no prior Sprint momentum. Do not label a Run-stop failure as a Sprint-ramp regression.
- The last legacy run found four valid male Run-stop grip failures, with right-arm overreach up to 4.663 mm at almost zero bank. Two poses cannot be fixed by longitudinal cart translation because their XY projection already exceeds arm length. Keep this known defect visible in results; it is not a blanket waiver or a successful all-cases baseline.
- Old fast-stop records also showed brief body/trousers shaft intersections. A weight-only clearance bump failed: virtually equal outgoing gait weights needed incompatible shifts for different poses. No fitted bump is part of this fixture.
- A fixed foot-Z amplitude threshold of .1 failed for loaded female **Walk** in all variants (about .062), while native leg matrices were unchanged. Compare gait-specific native motion and palette deltas; report raw diagnostic failures honestly.
- `cartLabRamp` reflects private cart-state fields. Changes to that implementation require updating this fixture; reflection errors must stop the record. Crossfade track lists can contain repeated upper-layer `Bob_Cart_Run` entries: do not sum them as root Run/Sprint weights.
- Capture is game-rendered video; world coordinates and native gait phases differ between records. Speed comparisons require measured positions/timestamps, and pose correctness requires matrix/mesh probes. A clip and completion marker alone are insufficient.

The copied source origins are listed in `manifest.json`. Legacy local profiles/launchers and frozen binaries are intentionally not dependencies.
