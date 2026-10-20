# Wooden cart multiplayer capture intake

[Development](../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../README.md)

Source-only fixture for one owner (`client1`), one real observer (`client2`) and a native menu Host (`mp_host=true`) or the default server fixture, on B42.21. It is connected by `tools/queue_checks/adapters/carts.py`, which owns fresh preparation, launch, attachment and verification. No copied core, binary, asset or profile is included here; the manifest retains historical intake metadata. Current evidence is recorded separately in each run report. The current placement uses native floor, free-space, vehicle, room and adjacency collision checks; decorations alone are allowed.

The server creates the loaded wooden cart in its inventory authority and sends it to the owner. The owner equips the same item in both hands and calls `player:updateHandEquips()` so the native equipment pipeline reaches the observer. Global Lua `sendEquip` is SERVER-ONLY; calling it from a client prevented earlier setup. The protocol waits for both clients to observe the owner's equipped cart, then the server broadcasts a single epoch 25 seconds in the future. The analyzer compares that epoch, one owner onlineID and one cartID on server and both clients.

The scenario lasts 15 seconds: idle 0–2, walk 2–5, turn 5–8, stop 8–10, reverse with Sprint modifier held 10–12, stop 12–15. Reverse retains the native controller's gait decision; the fixture does not force remote animation variables. State logging is 10 Hz. The observer faces the owner by setting only its own local actor's native direction. Hiding UI changes local UI rendering only. The default placement finder requires an existing loaded open 13x13 footprint. With `cart_fast_motion=true`, the fresh disposable menu Host instead creates a native 31x31 floor pad at Z7 after checking its entire empty footprint and halo; both clients must observe all961 replicated floors before positioning or arming. The owner starts four tiles east of the pad centre to leave room for the Sprint braking tail. No objects are cleared. Incomplete rendered-frame coverage is insufficient evidence; the analyzer requires owner and observer frames in every phase.

`cart_variant` selects `wooden-wheelbarrow` (default), `shopping-cart` or `metal-wheelbarrow`, with authoritative exact cart/cargo IDs and actual held/rendered model checks. `cart_fast_motion=true` extends motion to26 seconds, adding native Run, Sprint-turn and stop gates inside the checked pad bounds. It seeds the fixture owner's Sprinting XP on the server and waits for the native client snapshot; it does not force Sprint animation flags. `cart_actions=true` appends six wooden pickup/setdown completion, cancellation and repeat phases through native menu callbacks. These options are frozen selection inputs.

`cart_wall_exit="front"` selects an 18-second full-load frontal brace bank on the same disposable native Host wall/pad: forward at 1s, release at 6.5s, manual reverse at 7.5s, stop at 10s, restart at 10.8s, final release at 15.5s. It requires version 1, 13-field pose payloads with flag bit 8 and actual `ToolkitCartBrace`/`Toolkit_WoodCartBrace` on owner and observer, planted rendered feet/toes at both contacts, and removal of brace after release/reverse. The existing left/right sliding-wall gates remain unchanged. Observer approach penetration stays visible in the separate footprint diagnostics; a brace result does not close that defect.

## Adapter contract

Use the existing common `queue_checks.native.prepare` and `queue_checks.runner.run` unchanged, under their exclusive native lock and existing-process checks. The registered common adapter owns inputs, dependencies, fresh disposable profiles, mod approvals, preparation/fingerprints, process lifecycle, attaching probes before the epoch, artifact capture and cleanup.

Stage these source mappings in the adapter-owned project snapshot:

| Contribution source | Suite destination |
|---|---|
| client.lua | tests/native_queue/cart_motion_mp/client/ZZCartMP.lua |
| server.lua | tests/native_queue/cart_motion_mp/server/ZZCartMP_Server.lua |
| placement.lua | tests/native_queue/cart_motion_mp/shared/CartMPPlacement.lua |
| json.lua | tests/native_queue/cart_motion_mp/shared/CartMPJSON.lua |
| actions.lua | tests/native_queue/cart_motion_mp/client/CartMPActions.lua |

Use the exact selection shape in `manifest.json`. Before passing it to common prepare, replace `ffmpeg` with the absolute executable path and `videoRoot.client1/client2` with absolute, fresh output directories owned by the respective profiles. `VideoRecording.start(directory, ffmpeg)` creates `capture-*.mp4` inside each directory. Both clients receive the same complete mapping. Supply `disposable=true`; each Lua side refuses its absence. `QueueTestSelection` and `smoke-user.txt` remain common-core supplied. The host is intentionally loopback; accounts and password are disposable common-runner test credentials. EN/RU are original profile inputs, not localization assertions.

Prepare fresh owned disposable profiles, never existing player saves. Disable `toggleToRun`, `toggleToSprint`, `dblTapJogToSprint`, and pause-on-focus-loss. Use the sandbox settings in `manifest.json` and a fresh spawn configured by the runner. The finder searches loaded free squares around the actual actor; it fails if no clear 13x13 patch exists. Explicitly configure these inputs before sealing common provenance; do not rewrite a frozen snapshot afterward. This fixture mutates test inventory, position, Sprinting skill, equipment and local UI.

## Java composition and probes

Reuse `../wooden_cart_motion/Main.java` as the keyboard-input base. Insert the exact `MPMain.methods` text immediately before its unique `    public static void main(String[] args)` anchor. The self-check validates and compiles that composition; do not maintain a second copied Main.java. The added methods read per-player state and serialized cart-pose payload counters, seed test-only native Sprinting XP, turn only the observer's own local actor toward the owner, frame each role at its explicit zoom and hide local UI. Payload counters exclude UDP/RakNet headers, retransmission and ordinary native traffic.

Compile with explicit local `projectzomboid.jar`, `ZombieBuddy.jar`, and the candidate `PZToolkitJavaPatches.jar`, JDK 25+ and `--release 17`. Package the composed `net.alexredby.cartlab.Main` and nested classes as test-only `CartLab.jar`. Use mod id `CartLab`, `javaPkgName=net.alexredby.cartlab`, `javaJarFile=media/java/CartLab.jar`, `versionMin=42.21`, `require=\ZombieBuddy`, `ZBVersionMin=2.3.4`; provide the ordinary `42/` and `common/media/AnimSets/` layout. Let the common adapter approve the exact JAR hash with one ZombieBuddy agent and `policy=deny-new`.

The base Main has mandatory static `PZ_CART_RUNTIME_FILE` and `PZ_CART_COMMAND_FILE` environment variables even when no reload/poll is used. Supply explicit absolute adapter-owned paths; existing unused absolute files are acceptable. Never point at a personal live command channel. No environment/path fallback is included.

Compile `ClearanceProbe.java` against the same three JARs, package with `ClearanceProbe.mf`, and attach separately to both clients before the scenario epoch. The existing source-only `../wooden_cart_motion/evidence/AttachWoodenWheelProbe.java` is the explicit attach helper; it is not duplicated here. Attach arguments are the selected client PID, built probe JAR, and that client's absolute output directory. PID ownership/checking is adapter-owned. Stop via agent argument `stop` before cleanup. The probe refuses an existing `body-clearance.jsonl`. It captures at the exit of `CartGrounding.render`, including the remote gate's early return, so an uncorrected observer pose remains measurable.

The same probe writes `transition-solve.jsonl` for every wooden transition solver invocation, including cancellation recovery. It records success and nested solver refusals, with pre-solve arm geometry for failed reach. This trace is unthrottled; compare its per-frame results with the six action windows separately from the sampled presentation coverage.

The candidate production JAR must expose `CartSteeringHooks.enabled/lean`, and the base's existing `states/State.pace/sprintMomentum/load/heading` plus `CartLegPace.targetSpeed` contract. Toolkit >=0.1.58 and JavaPatches >=0.1.15 alone do not guarantee those candidate APIs. Required external mods are ZombieBuddy, SaucedCarts and saucedwheelbarrow. Required video APIs are `toolkitVideoStart`, `toolkitVideoStatus`, `toolkitVideoStop` and an explicitly supplied FFmpeg executable. Missing APIs/attachments are errors, never empty diagnostics or PASS.

## Offline verification

```sh
python3 tests/native_queue/contributions/wooden_cart_multiplayer/self_check.py
python3 tests/native_queue/contributions/wooden_cart_multiplayer/self_check.py \
  --game-java-dir "$PZ_GAME_JAVA_DIR" --jdk "$JAVA_HOME" --patch-jar "$PZ_PATCH_JAR"
python3 tests/native_queue/contributions/wooden_cart_multiplayer/analyze.py \
  --profile "$PZ_CAPTURE_DIR" --output "$PZ_ANALYSIS_DIR/cart-mp-comparison.json"
```

The self-check never launches the game. Lua syntax needs Lua/LuaJIT or `--lua`; compilation needs all three explicit dependency arguments. Omitted checks print SKIPPED. Temporary synthetic logs and class files are removed afterward.

Current fixture path guards accept POSIX absolute paths only, matching the current common launcher. Windows drive/UNC paths are not ported.

The analyzer always reads the original frozen `selection.json` and accepts the original suite `cart_motion_mp` and registered common-runner alias `wooden_cart_multiplayer`, with kind `mp`, mode `toolkit` and exactly case `owner_observer_motion`. Capture 07 receipts omit `mode`; its absence is accepted only after this canonical input check, while an explicitly wrong receipt mode is rejected. The report records `modeSource=selection.json`; logs are never rewritten. This does not change the `live_after_parameterization=false` label. It also requires `execution.json`, all three `ROLE-launch.log` files and both `ROLE/body-clearance.jsonl` files. It refuses existing output. It validates finite numeric fields, actual JSON booleans, unique JSON keys, owner/cart identities and successful capture completion without probe errors. Every state/pose window needs at least five distinct samples, coverage within 350 ms of each edge, at least 55% time span and no gap over 600 ms. Windows are idle .3–1.7, walk 2.5–4.5, turn 5.5–7.5, first stop 8.5–9.5, reverse 10.5–11.5, settled stop 13–14.5 seconds after the server epoch. Both owner and observer need rendered frames in every window. Missing FOV/LOS frames are incomplete evidence, not proof of a replication bug.

The identity-aware source probe records `primary` and `secondary` IDs in each pose row. Pose schemas lacking these IDs are rejected.

Output contains raw wheel-floor and palm-handle errors, gait/pivot/pace/bank state and final position deltas. The extra fast bank also requires actual native Run/Sprint movement and steering, a settled owner stop, shared pad readiness and every sampled owner position inside its margin; actions require all six owner/server/observer receipts. Shopping and metal captures preserve raw transforms without applying wooden-only contact calibration. Mesh/contact/palm constants are B42.21 calibrated measurements for the current wooden cart and native male/female rig. Changed assets need recalibration. These diagnostics are not body/shaft mesh-intersection testing or animation equivalence thresholds. `evidenceComplete=true` means coverage was verified; no animation equivalence PASS is emitted. Observer bank can stay zero during an owner turn, with different hand reach and wheel-floor placement. Keep those replication discrepancies visible and require explicit pose review.

Visual QA remains limited: `UIManager.setVisibleAllUI(false)` did not hide character-info/chat windows, which still occluded the hands in source images. Review current captures separately; legacy UI visibility calls alone do not certify unobstructed framing.

`status=captured` denotes complete capture receipts in the common report, never a functional pass. Common runner lifecycle `completed` is necessary but insufficient; negative geometry and replication measurements remain visible for review.
