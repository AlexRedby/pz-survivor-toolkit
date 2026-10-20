# Wooden cart motion scenarios

[Development](../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../README.md)

Source fixtures are connected through `tools/queue_checks/adapters/carts.py`. The common runner stages fresh profiles, owns probe attachment and records captures separately from functional passes. The manifest retains historical intake metadata. `self_check.py` checks the manifest, files, Lua parsing and optional Java compilation. It never starts Project Zomboid.

The Java fixture supplies native keyboard input (`drive`, `gait`) and reads the current cart bank, root-speed ramp and animation tracks. `bootstrap.lua` equips carts, creates its HUD and prepares the disposable floor. `scenario-clips.lua` records 16 cases: two sexes, empty/full cargo, and comparison/direct Sprint/gait transitions plus a Run-stop control. The full 12-second records include turns, stops and returns to walking. It samples every 100 ms.

## Common runner

Choose one case per fresh lifecycle: `sprint` (16 records), `reverse` (20), `reversal` (20), `stop` (24) or `stationary` (20). All use the same adapter-owned profile, area, launcher and probe setup. Supply candidate resources once in a JSON file:

```json
{
  "patch_jar": "/absolute/candidate/PZToolkitJavaPatches.jar",
  "mesh_fbx": "/absolute/original/Wheelbarrow_wood.fbx",
  "ffmpeg": "/absolute/ffmpeg",
  "ffprobe": "/absolute/ffprobe",
  "mod_sources": {
    "PZSurvivorToolkit": "/absolute/checkout/PZSurvivorToolkit",
    "PZToolkitJavaPatches": "/absolute/checkout/JavaPatches/build/PZToolkitJavaPatches"
  }
}
```

```sh
python3 tools/check_action_queue.py prepare /tmp/cart-stop-fresh \
  --suite wooden_cart_motion --cases stop --language RU \
  --game "$PZ_GAME_JAVA_DIR" --jdk "$JAVA_HOME" \
  --workshop "$PZ_WORKSHOP" --config /absolute/cart-resources.json
python3 tools/check_action_queue.py resume /tmp/cart-stop-fresh
python3 tools/check_action_queue.py report /tmp/cart-stop-fresh
python3 tools/check_action_queue.py matrix /tmp/cart-stop-fresh/report.json
```

Coordinate the GUI slot before `resume`. Preparation compiles fixtures and records exact source/mod/JAR hashes, but never launches the game. Do not rebuild or edit those inputs between preparation and reporting. Use a new output path for another case; no copied old profile or save is needed. Reports retain `captured` and `needs-review` separately from animation quality. Reversal retains measured rest-before-direction-change, backward gait and braking-displacement checks; those motion gates remain separate from grip/mesh and visual quality.

The adapter reads full `client1-launch.log` when available because high-rate scenario output rotates `console.txt`. Both stop and pose analyzers receive that same original path through `--log`; logs are never rewritten. A standalone analyzer can also accept `--log /absolute/full-stdout.log`.

## Clean capture UI

SP automated captures hide the interface by default; manual CartLab sessions keep it visible. Set `"cart_hide_ui": true` or `false` in the resource JSON to choose explicitly. This changes only the disposable CartTestArea process, without saving personal options or key bindings. The render gate hides inventory panels, the body silhouette, hotbar and fixture overlays while native updates and action handlers keep running.

Press **F9** to show/hide the interface during a CartLab session. An existing F9 binding takes priority; in that case use the fixture Lua call `cartLabCaptureUI(true)` to hide it or `cartLabCaptureUI(false)` to restore it. Leaving the test world or reloading the fixture restores the captured UI visibility. Engine debug/error windows remain visible.

## Relative movement and obstacle matrices

Use `--cases motion-matrix` for 36 current-control scenes: male/female, empty/full,
Walk/Run/Sprint, with measured arcs and screen-up/down slaloms. Arc scenes record
90 seconds and cover both directions at 45/90/135/180 degrees, steering release
and stopping on an arc. Slalom scenes record 20 seconds with 300/600/900 ms side
switches. Forward+Left/Right turns; Backward remains reverse. A scene never resets
the actor's position or heading during its recording.

Use `--cases obstacle-matrix` for 72 scenes across the same body/load/gait axes:
frontal bracing, both wall-slide directions, corner contact and real open/closed
doors. Every scene records 16 seconds, including explicit manual reverse and
release. Run/Sprint open-door scenes start manual reverse at 4 seconds after a
measured settled-neutral interval of at least 500 ms; other scenes start at 8
seconds. All release reverse at 13 seconds. The earlier fast-door return leaves
room to bring the whole cart back after its longer coast through the doorway.
Independent bare native controls establish the obstacle layouts. Frontal,
corner and door scenes require normal backoff; slides require manual backward
travel along the wall. The separate wall-manual-exit banks cover reaching a wall
end and turning out. Contact is checked against the current native collision
envelope, while rendered mesh/wheel penetration is checked independently.
The health overlay is hidden only in the disposable test process, without saving
user options.

Both banks retain the shared mesh/grip/native-pose probes. Their dedicated
`analyze-motion-matrix.py` and `analyze-obstacle-matrix.py` report measured behavior.
Slalom reversals include the existing angular inertia: report sampled old-direction
excursion and response timing separately from eventual steering. A short press
that still produces net yaw in the previous direction remains an explicit response
limitation even if the bounded-inertia checks pass. Completion does not establish
animation equivalence; grip/body/floor checks also do not establish temporal smoothness. Selected-scene runs retain
the common partial/debug status. Historical absolute-input maneuver banks do not
establish coverage of the current cart-relative controls. Host observer wall
penetration remains a separate unresolved gate.

## Selected-scene debug captures

Add `--cart-scene male-full-corner` to a fresh `prepare --suite wooden_cart_motion --cases path` command above to record that scene only. Repeat the flag for more exact scene IDs, or set `cart_scenes` to an array of exact names in the resource config. Names match the video/log scene names; unknown, duplicate and empty selections are rejected before profile creation. Execution preserves the original bank order. Omit the filter to retain the full matrix. Collision captures keep their three bare controls because scene layouts depend on them.

The selected IDs are pinned in the snapshot. Debug reports retain videos, mesh diagnostics and body/grip samples, set `diagnosticOnly` and `partialCoverage`, and stay `needs-review`; the coverage matrix shows `partial`. They do not establish an animation-quality PASS, even if every scene ID was explicitly selected. The `interruption-fast` and `approach` banks run their lifecycle oracle for the selected scenes only; other selected banks retain diagnostic capture without the full-bank motion oracle. A complete full-bank run remains the final gate. The original recording durations, disposable-world checks, probe-error guards and process cleanup are unchanged.

## Parameters and adapter boundary

### Authored wooden-cart actions

Authored pickup/setdown body clips are the default for supported single-player actors. Omit `cart_authored_clip` from the SP resource JSON to test that production selection; `false` selects the procedural comparison and `true` forces the authored variant. The fixture changes `ToolkitWoodCartClipPilot` only for an explicit selection. MP retains the procedural version. An unsupported native retirement API selects the procedural default; explicitly forcing authored clips fails fast. Pickup and reverse setdown use native `m_TrackTimeToVariable` playback, with deferred movement disabled. Dynamic hand contact and the cart transform remain constrained by Java. Cancellation and immediate retry preserve the latest displayed pose through the bounded exact-owner handoff, so test them separately from successful actions.

The editable normalized pose samples are `assets/animations/wood_cart_pickup.json`. Rebuild the game asset with `python3 tools/cart_clip_bake.py --template "$PZ_GAME_JAVA_DIR/media/anims_X/Bob/Bob_Idle.x" --input assets/animations/wood_cart_pickup.json --output PZSurvivorToolkit/42/media/anims_X/Bob/Toolkit_WoodCart_Pickup.x --name Toolkit_WoodCart_Pickup`. The writer validates all 45 rigid model-space bones. Compile `tools/CartClipCheck.java` against the installed game JAR to check a generated clip with the native importer; it accepts the clip and a TSV containing time, bone name and 16 column-major floats per row. Offline import checks do not replace native transition, contact and ownership checks.

Select `--cases interruption-matrix` for all 48 cancellation scenes (both body models and loads, pickup/setdown, three phases and cancel/movement). Select `--cases repeat` for twelve 20-second rapid-action scenes: immediate completed-action chains and pickup/setdown cancellation followed by an immediate retry, across both body models and loads. `analyze-repeat.py --profile CACHE --log LOG --output REPORT` checks the actual native start and per-track identity/time through the outgoing fade, alongside ownership, cargo and pose evidence. A queued command alone cannot establish a rapid restart. Partial scene selections retain diagnostic status.

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

The coordinates are the original B42.21 calibration, not portable world discovery. The adapter must establish that the whole configured ground footprint is loaded. Required fields have no hidden path/profile defaults. The area accepts finite grid parameters and a bounded size up to 96; it retains the original object/floor/actor/collision validation and refuses any world other than single-player `CartTestArea`. The SP adapter sets `PZ_CART_TEST_PAD=true`: CartLab then keeps the native chunk window at least 25x25 chunks (200x200 tiles), enough to retain the complete pad from every safe player position. Streaming still follows the player. MP explicitly disables this test-only override. Bootstrap checks and logs the actual chunk width and render dimensions before floor preparation.

Create a **fresh, owned, disposable profile** with the manifest options/sandbox settings. Do not reuse a player save, delete an existing save automatically, or copy an old investigation profile. The fixture changes test inventory, clothing, Sprinting skill and floor tiles. It validates the complete footprint before creating floors and never clears unexpected objects.

Compile `Main.java` against local B42.21 `projectzomboid.jar` and `ZombieBuddy.jar` with JDK 25+ and `--release 17`. Package it as a test-only `CartLab` mod exposing `net.alexredby.cartlab`; approve the exact JAR hash in the isolated ZombieBuddy config. The manifest records the original JVM/game arguments as adapter templates, not an executable launch command. Supply the platform runtime/native libraries and exactly one ZombieBuddy agent with `policy=deny-new`. The macOS first-thread flag is platform-specific.

The live fixture requires Toolkit >=0.1.58 and JavaPatches >=0.1.15 **with the current candidate B42.21 cart-motion changes integrated**. Version numbers alone are insufficient: `cartLabRamp` reflects `State.pace`, `sprintMomentum`, `load`, `heading` and calls `CartLegPace.targetSpeed`. These APIs must be present in the selected candidate bytes; the rebased cart branch integrates them, while older main snapshots may not. A missing reflected member must remain an exception that stops the record, never an empty diagnostic or PASS.

The adapter must own the exclusive native queue lock, existing-process checks, profile preparation, mod installation/approvals, launcher, probe agents, analyzers and cleanup. Those operations are implemented in the common adapter, outside this source contribution. Load the config, test area and bootstrap; wait for `BOOTSTRAP_READY`; then load the scenario. Missing bridges/configuration fail before the scenario changes the player. Bootstrap also checks the disposable world before equipping anything.

The fixture requires single-player and RU language in `options.ini`; other locales and MP have not been validated. Case IDs/log markers are stable ASCII strings and do not establish localization coverage.

## Checks and evidence

```sh
python3 tests/native_queue/contributions/wooden_cart_motion/self_check.py
python3 tests/native_queue/contributions/wooden_cart_motion/self_check.py \
  --game-java-dir "$PZ_GAME_JAVA_DIR" --jdk "$JAVA_HOME" --patch-jar "$PZ_PATCH_JAR"
```

Lua syntax requires `luajit` or `lua` on PATH, or `--lua`. Java compilation requires both explicit dependency paths; omitted checks are reported as skipped. Compilation output goes to a temporary directory. There are no runtime binaries, saves, screenshots, videos, copied mods or game assets in this contribution.

Keep `[WOOD_BANK]` markers stable for existing analyzers. A complete record needs one unique `COMPLETE` marker per selected case (16/20/20/24/20/32/20/20 for sprint/reverse/reversal/stop/stationary/maneuvers/collision/footprint), valid per-case windows and a matching `ALL_COMPLETE cases=N`. Check `FAIL` and rejected video starts/stops. The manifest criteria additionally require grip, actual mesh, floor and original hip/leg/arm probes. Their source, dependencies, build commands, offline checks and limits are preserved in [evidence/README.md](evidence/README.md). The common adapter runs these probes and analyzers; missing instrumentation means **not verified**, not PASS.

## Known traps and limits

- The calibrated path requires a loaded 96x96 pad. A larger pad can have far corners streamed out after a reset. Per-tick checks validate the current tile; before each record the scenario waits 1.8 seconds, then retries the **full** pad check for up to 6 seconds. An unloaded square still aborts; do not bypass it.
- Synthetic input patches both `GameKeyboard.isKeyDown` and `isKeyDownRaw`. `drive=-1` releases the override; `drive=0` is neutral input. Logical key bindings are used, not OS keyboard events. Runtime/profile options must disable toggle/double-tap Run/Sprint.
- Sprint requires controlled skill 10. The `runstop` control deliberately has skill 0 and no prior Sprint momentum. Do not label a Run-stop failure as a Sprint-ramp regression.
- Male Run-stop grip can fail from right-arm overreach, including near-zero bank. Do not waive these failures or treat a partial motion pass as an all-cases baseline; inspect arm reach and cart pose together.
- Fast-stop body/trousers shaft clearance remains a separate unresolved geometry check; gait-weight adjustments must not be treated as a general clearance fix. Male empty-cargo reverse-left arcs also need an explicit trousers/left-shaft intersection check, even when motion gates pass.
- A fixed foot-Z amplitude threshold of .1 failed for loaded female **Walk** in all variants (about .062), while native leg matrices were unchanged. Compare gait-specific native motion and palette deltas; report raw diagnostic failures honestly.
- `cartLabRamp` reflects private cart-state fields. Changes to that implementation require updating this fixture; reflection errors must stop the record. Crossfade track lists can contain repeated upper-layer `Bob_Cart_Run` entries: do not sum them as root Run/Sprint weights.
- Capture is game-rendered video; world coordinates and native gait phases differ between records. Speed comparisons require measured positions/timestamps, and pose correctness requires matrix/mesh probes. A clip and completion marker alone are insufficient.

The copied source origins are listed in `manifest.json`. Legacy local profiles/launchers and frozen binaries are intentionally not dependencies.

`scenario-reverse.lua` is a separate 20-case matrix: backward start/stop, held Run/Sprint modifiers, reverse arcs from ±22.5deg and a forward 180-degree U-turn composed of two 90-degree turns, plus a 90-degree turn requested directly from idle. `cartLabPoseHeading` sets both actor/animation headings and resets cart steering only during fixture setup; it is not the stationary-turn implementation. Select the common runner case `reverse`; the adapter loads this source after BOOTSTRAP_READY. The new scenario requires Toolkit>=0.1.58/JavaPatches>=0.1.15; do not infer success from its source or completion marker alone.

Analyze its 20 motion cases with `python3 tests/native_queue/contributions/wooden_cart_motion/analyze-reverse.py --profile "$PZ_CAPTURE_DIR" --output "$PZ_ANALYSIS_DIR/reverse-motion.json"`. This checks native Walk despite speed modifiers, authored backward pace, sign/heading, reverse arcs, 180/90-degree controls and stop position. It requires samples for every completed case and refuses an existing report. Its `motionPass` deliberately does not claim grip/mesh/floor or visual success; use separate probes/analyzers from `evidence/`.

Backward cases require samples from every requested gait stage, away from switch boundaries, with the matching `requestedGait`. Reverse arcs also require measured backward displacement along the observed heading; a stationary or forward-moving actor cannot pass through negative animation variables alone. Offline checks cover missing modifier stages, wrong gait requests, invalid booleans and stationary/forward arcs.

The reverse analyzer checks motion only; it does not claim grip, mesh, floor or visual success. Geometry and rendering require their separate probes, and any failed intersection or reach criterion remains a failure.

`scenario-reversal.lua` records 20 forward/reverse transitions: Walk, Run, Sprint, rapid cancellation/release and a command change on an arc, for both sexes and cargo states. It requires the >=0.1.59/0.1.16 candidate with `State.reversal`; `cartLabReversal` reads its latched direction, requested sign, braking/neutral state and accepted displacement. Sampling is every 25 ms. A complete record has `ALL_COMPLETE cases=20`. Keep character-info/chat hidden and disable the MiniHealthPlus overlay in the disposable profile so hands/feet remain visible. The separate `analyze-reversal.py` retains measured rest before direction flips, forward braking displacement and walking-only reverse gates. Use `--profile "$PZ_CAPTURE_DIR" --log "$PZ_FULL_STDOUT" --output "$PZ_ANALYSIS_DIR/reversal-motion.json"` for a standalone report. It refuses existing output; completion alone is not a motion or pose PASS.

At 25 ms sampling the game rotates `console.txt` during this matrix. Retain full native stdout and select each successful `COMPLETE` attempt by its recorded start timestamp; a failed/retried framebuffer recording must not be combined with the successful attempt.

`scenario-stop.lua` records 24 wooden-cart braking cases: Run/Sprint release, short acceleration, resumed input, a reverse command during braking and stopping on an arc, for both sexes and cargo states. It requires the >=0.1.61/0.1.18 candidate. `cartLabBrake` reads the stop state separately so older reversal scenarios keep their existing API. Sampling is every 25 ms; completion is `ALL_COMPLETE cases=24`. Its HUD records wall elapsed time and input stage in the video, so dropped render submissions do not masquerade as exact event-relative video timestamps. The stop contract requires complete scene windows, the actual heavy-item stop clip, accepted coasting, stable hand/mesh/floor contact and immediate cancellation on new input. Bootstrap/setup frames are outside the scene windows and require separate review when changing setup or pickup behavior. Captures from earlier candidates do not verify a rebuilt or rebased candidate.

Run `python3 tests/native_queue/contributions/wooden_cart_motion/analyze-stop.py --profile "$PZ_CAPTURE_DIR" --output "$PZ_ANALYSIS_DIR/stop-motion.json"` against the full native stdout. It requires all 24 cases and samples, selected heavy stop tracks, observed coasting, bounded settling and cancellation on new input. It refuses to overwrite a report. Grip, actual body/trousers geometry, wheel contact and visible foot motion still require their separate probes and video inspection. If `wood-wheel-native.csv` is present, straight Run/Sprint stops also report cart return relative to the stopped actor, using the monotonic probe clock: excursion, sample cadence, raw speed changes and maximum 100 ms average return speed. These are descriptive comparisons, without a calibrated quality PASS threshold. Sparse console samples are not used as a substitute for native temporal measurements.


`scenario-stationary.lua` requires Toolkit>=0.1.61/JavaPatches>=0.1.19 with the stationary-turn controller. Its 20 scenes cover both sexes and cargo states: left/right from settled Idle, release/cancel/restart, held Run after the pivot and held Sprint followed by another 90-degree command. The last scene reaches 180 degrees through consecutive turns; direct opposite input remains reverse. Each scene retains the shared 12-second geometry/probe window and attempts 25 ms sampling. For a fresh capture use the Common runner commands above with `--cases stationary` and a new profile path, such as `/tmp/cart-stationary-fresh`.

```sh
python3 tests/native_queue/contributions/wooden_cart_motion/analyze-stationary.py \
  --profile "$PZ_CAPTURE_DIR" --log "$PZ_FULL_STDOUT" \
  --output "$PZ_ANALYSIS_DIR/stationary-motion.json"
```

The analyzer requires exactly 20 selected successful attempts, full finite sample coverage, native root-layer strafe clips whose phases advance, the matching lateral direction, walking-only pivot flags, heading convergence/exit, cancellation/restart and resumed fast movement. `cartLabStationary` reads `heading`, `target`, `stationary`, `stationaryRoot`, accepted displacement and the actual steering axle; it changes no controller state. Header and diagnostic boundaries are parsed separately, so native track suffixes cannot overwrite coordinate fields. Failed video attempts are excluded by the successful start timestamp without rewriting stdout.

`wood-wheel-native.csv` from the existing render probe is mandatory. Each contiguous pivot needs native wheel coverage: actor+axle drift must stay within .025 tiles; rendered wheel-center drift and wheel-phase rolling excursion must each stay within .05 tiles, including the calibrated approximately .01 tile lateral offset from the steering axis. These are functional bounds, not a calibrated visual-quality threshold. Duplicate millisecond timestamps in render samples do not invent extra temporal coverage. Individual update ordering and inter-sample peaks require the Java checks and game review. The existing grip/body/trousers/floor probes still run for every scene, and `captured` retains a failed motion report for review. A completed capture never implies an animation-quality PASS. Keep raw stdout, probes, videos and runner source/mod manifests with the report; no live stationary result has been recorded by the offline checks.

## Direction changes and U-turns

Select `--cases maneuvers` for 32 twelve-second scenes: left/right redirection from rest and Run, cancellation/restart, reverse from rest, Sprint reversals with an interrupted first request, and forward 180-degree arcs in both directions with an interrupted second arc. Both body models and empty/full loads use the same input schedule. A directly opposite command remains reverse; U-turns use successive 90-degree targets.

The adapter retains `maneuvers-motion.json` beside the separate grip, wheel, body/clothing and runtime results. The motion analyzer requires every selected attempt and input stage, measured heading/position changes, rest before reversing, cancellation/restart and final settling. Full capture and `motionPass` do not establish visual or geometry quality. Use exclusive admission (`--exclusive` at preparation) for comparable cadence/video measurements and coordinate the desktop slot before `resume`.

## Native collision and recovery

The preserved pre-guard collision baseline has three bare-character controls followed by 16 twelve-second cart scenes: frontal block/Run, wall sliding/Run, a blocked stationary pivot in a corner, and a one-tile passage in both directions. Its standalone `analyze-collision.py` remains available for those frozen captures. Fixture drive IDs 5–8 hold two adjacent screen keys to request world cardinal directions; existing IDs 1–4 are unchanged. The current runner's `collision` selection aliases the guarded `footprint` matrix below, since the old actor-contact expectations no longer apply when the cart stops first.

Sprint into a wall invokes native impact/getup and temporarily disables cart steering. This basic collision matrix requires finite enabled-state measurements throughout; it does not cover protected impact recovery. That needs a separate state-aware oracle, rather than accepting missing grip/state samples or `NaN` wheel phase.

`obstacles.lua` creates only registered native N/W walls in the disposable pad. The full pad scan keeps checking every object identity, floor, actor, vehicle and both-direction collision edge; unexpected objects/edges and missing wall collision fail. All registered walls are removed before completion. The control samples and `collision-motion.json` validate actual character position, accepted heading/wheel motion, blocked intervals and recovery. The held cart model has no independent rigid body; a mesh entering a wall before the character stops is an explicit limitation, not a cart-contact PASS. Grip, floor, clothing/body geometry and runtime messages retain their separate reports.

The quiet-wheel check compares wheel phase with the wheel-center displacement reconstructed from actor position, heading and calibrated axle/pose clearance. A gait transition can move the cart while the actor is still; its matching wheel roll is required. This sampled telemetry check does not replace rendered mesh/video review.

## Wooden cart obstacle envelope

Select `--cases footprint` with JavaPatches>=0.1.20 for the guarded candidate. It reuses the collision fixture with `config.footprint=true`: 16 wall/diagonal/corner/passage scenes across both body models and loads, plus four male/empty edge scenes for a closed door, an open door, reverse recovery from an explicitly overlapped initial pose, and a Run request after stopping at contact. The same three bare controls run first. Reverse input is chosen opposite the measured heading after the blocked maneuver.

Measured windows start after pad validation and encoder startup. A failed recording resets both drive and gait and repeats the layout/pose/settling pipeline before a new attempt; each attempt retains its own layout and start marker. The pad checks static collision edges and native special objects separately, since B42's adjacent-cell query with a nil actor skips doors.

The original mesh has a conservative front extent of 1.26 tiles through walking/bank poses and 1.62 through fast-pose clearance; lateral bounds are within [-.308,.326]. The guard checks both rear caps and two longitudinal native rails, sweeps the planned step and rechecks the accepted native displacement/yaw. It reserves the fast envelope through outgoing tracks and suppresses fast-gait promotion when that envelope cannot fit. An initially intersecting cart must back straight out before turning. This is a conservative tile-wall/door guard: full vehicle clearance, remote authority and other meshes require separate calibration and coverage.

`analyze-footprint.py` requires `[CART_FOOTPRINT_STATE]` telemetry, native grounding updates in `wood-wheel-native.csv` and same-frame world origin/angle in the clearance probe. Movement sanity uses adjacent native timesteps to cover deferred animation/update ordering, rather than the spacing of Lua log timestamps. A rendered slot must match both position and heading of one of its two bracketing actor samples. Corner contact may be enforced by native actor collision before the cart guard; quiet held input must still show an unresolved turn or an observed guard rejection.

The analyzer checks the actual original wooden vertices and the rotating tire's support bound against fixture wall planes, including the open gap. Missing world/probe data is unverified. Its motion/footprint results remain separate from grip, body/trousers geometry and runtime audit; an explicitly invalid recovery setup is never a visual pose PASS.
