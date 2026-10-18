# Wooden cart evidence sources

[Development](../../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../../README.md)

Offline analyzers and attachable, read-only render probes for the calibrated B42.21 wooden wheelbarrow. These files do not launch a game, create a profile, synthesize input or take the native queue lock. The existing queue adapter must own those operations and the disposable profile. A compile/self-check PASS is not a live motion PASS.

## Sources and dependencies

- `WoodenWheelNativeProbe.java`, `WoodenWheelProbeCheck.java`, `AttachWoodenWheelProbe.java`: the wheel/grounding/hip/leg/arm palette sensor from the wooden transition investigation. The sensor samples approximately 30 Hz and records native grounding and split-draw data. Its first GPU read also extracts `WheelbarrowWood.bin` (8 little-endian float32 values per vertex) into the explicit output directory. The second proof, after wheel phase changes, updates the hash proof JSON. The original calibrated VBO hash remains an explicit check, not an asset bundled here.
- `WoodenWheelProbeLifecycleTest.java`: deterministic stop versus late-callback regression. CSV writes and writer detachment share the lifecycle lock; callbacks after stop skip recording, while real I/O failures remain errors.
- `GripPoseProbe.java`, `GripPoseProbeCheck.java`: the grip reference sensor; copies matrices **before** `CartGrip.grip` changes them and records success, false returns and exceptions. Do not discard false results.
- `ClearanceProbe.java`: final rendered body palettes and held cart matrix, from the clearance instrumentation source used by the fixture. The running JAR itself contained classes only; no decompiled game classes were copied. `ClearanceProbeCheck.java` checks instrumentation generation and output safety.
- `check-clearance.py`, `check-hip-actual.py`, `analyze-native.py`: mesh and native pose analyzers. The first two now share `clearance_geometry.py` instead of executing another script's source. All input/output paths are explicit.
- `fbx_mesh.py`, `shaft_components.py`, `actual_mesh.py`: original binary FBX reader and wooden shaft topology/intersection/distance calculations, with explicit mesh loading instead of import-time access to an investigation directory. No FBX, native vertex buffer or body mesh is included.

Java dependencies are local `projectzomboid.jar`, `ZombieBuddy.jar` (includes Byte Buddy), the compiled candidate JavaPatches classes and JDK 25+; source targets Java 17. Python requires Python 3 and NumPy. No dependency is downloaded or installed by these files. The probes reflect candidate `CartWheelSpin.phase`, `CartGrounding.render` and `CartGrip.grip`; incompatible candidates must fail instrumentation or the capture checks.

## Offline checks

From the repository root, supply local paths:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/native_queue/contributions/wooden_cart_motion/evidence/self_check.py \
  --game-java-dir "$PZ_GAME_JAVA_DIR" --jdk "$PZ_JDK" \
  --toolkit-classes "$PZ_TOOLKIT_CLASSES"
```

Without those three Java parameters, the check explicitly skips Java. Python syntax is compiled in a temporary directory. Geometry self-checks cover crossing, coplanar overlap/disjoint triangles, containment, distances, AABB separation and column-major native skinning. Java checks compile every probe, generate advice and check copied grip inputs, coordinate conversion, matrix deltas and refusal to overwrite a capture. No attach operation runs.

Synthetic analyzer regressions also require actual body/cart and body/trousers intersection samples in every completed case. Empty or incomplete geometry evidence and nonfinite native measurements fail instead of passing through empty `all()` or ignored `NaN` values.

## Agent packaging and attachment boundary

Compile with explicit dependencies into an adapter-owned build directory, outside this source tree:

```sh
"$PZ_JDK/bin/javac" --release 17 \
  -cp "$PZ_GAME_JAVA_DIR/projectzomboid.jar:$PZ_GAME_JAVA_DIR/ZombieBuddy.jar:$PZ_TOOLKIT_CLASSES" \
  -d "$PZ_EVIDENCE_CLASSES" tests/native_queue/contributions/wooden_cart_motion/evidence/*.java
```

The classpath separator above is for Unix; use `;` on Windows. Package each probe with its matching `.mf` and compiled classes using the JDK `jar --create --file ... --manifest ... -C "$PZ_EVIDENCE_CLASSES" .`. The three manifests declare `Agent-Class` and retransformation only. They are not launch configurations.

The adapter may use `AttachWoodenWheelProbe PID AGENT_JAR ABSOLUTE_OUTPUT_DIRECTORY` for each agent. The directory must already exist; all three accept `stop` as the third argument to close their output. The PID and paths must come from the adapter's owned test process/profile, not process discovery in these files. Existing `wood-wheel-native.csv`, `wood-grip-poses.jsonl` or `body-clearance.jsonl` are refused rather than truncated. Stopping closes output; it does not unload installed advice. Agent deployment/retransformation permissions and cleanup remain adapter responsibilities.

Capture outputs are `wood-wheel-native.csv`, `wood-wheel-mesh-proof.json`, `WheelbarrowWood.bin`, `wood-grip-poses.jsonl`, and `body-clearance.jsonl`. Preserve console errors with them. Profile location is explicit in the adapter; agents use the supplied output directory rather than the game's cache/profile default.

## Analysis commands

`PZ_CAPTURE_DIR` is the profile/capture directory containing `console.txt` and probe outputs. `PZ_MESH_FBX` points to the locally installed `Wheelbarrow_wood.fbx`. `PZ_CAPTURE_DIR/WheelbarrowWood.bin` must come from the actual capture. Outputs must be outside this source tree; existing analysis files are refused.

```sh
python3 tests/native_queue/contributions/wooden_cart_motion/evidence/check-clearance.py \
  --game-java-dir "$PZ_GAME_JAVA_DIR" --mesh-vbo "$PZ_CAPTURE_DIR/WheelbarrowWood.bin" \
  --capture "$PZ_CAPTURE_DIR/body-clearance.jsonl" --output "$PZ_ANALYSIS_DIR"
python3 tests/native_queue/contributions/wooden_cart_motion/evidence/check-hip-actual.py \
  --game-java-dir "$PZ_GAME_JAVA_DIR" --mesh "$PZ_MESH_FBX" \
  --mesh-vbo "$PZ_CAPTURE_DIR/WheelbarrowWood.bin" \
  --capture "$PZ_CAPTURE_DIR/body-clearance.jsonl" --output "$PZ_ANALYSIS_DIR"
python3 tests/native_queue/contributions/wooden_cart_motion/evidence/check-hip-actual.py \
  --pants --game-java-dir "$PZ_GAME_JAVA_DIR" --mesh "$PZ_MESH_FBX" \
  --mesh-vbo "$PZ_CAPTURE_DIR/WheelbarrowWood.bin" \
  --capture "$PZ_CAPTURE_DIR/body-clearance.jsonl" --output "$PZ_ANALYSIS_DIR"
python3 tests/native_queue/contributions/wooden_cart_motion/evidence/analyze-native.py \
  --profile "$PZ_CAPTURE_DIR" --output "$PZ_ANALYSIS_DIR"
```

The AABB result is conservative: positive gap proves separation; overlapping boxes are **inconclusive**, not proof of clipping. The actual triangle check exits nonzero for any captured intersection. It checks the chosen body/trousers hip triangles against six calibrated shaft/brace components, including containment in closed solids. It verifies VBO vertices against FBX after import Z reflection. This does not prove native triangle-index identity or all clothing coverage.

The shared adapter writes `selected-scenes.json` with the exact selected IDs and recording/measurement windows, and passes it to `analyze-native.py --scenes /absolute/selected-scenes.json`. This path requires ordered, completed video receipts with matching start times, durations and `ALL_COMPLETE cases=N`; a `CASE` start never counts as completion. Input/path phase labels come from the successful attempt's recorded events rather than another bank's schedule. Equal-time probe/input records are labelled `transition` because separate streams do not establish their order. Movement analyzers separately check whether the observed commands and motion meet the scenario's requirements.

For offline re-analysis, use the saved profile/log and a contract generated from the original bank/selected IDs, with a **new output directory**. Generate body/trousers triangle outputs there first using the commands above, then run the aggregate analyzer with `--scenes`. It preserves existing aggregate output and records SHA256 hashes of its inputs and analyzer sources in `native-metrics.json`. This is derived analysis of the old capture, not verification of new production code or a replacement for its original runtime report.

The legacy invocation without `--scenes` retains the original **16-case WOOD_BANK** protocol and explicit timing flags for archived commands; `--partial` remains diagnostic only and is no longer used by the shared adapter. Both paths check grip, unchanged hips/legs, arm links and wheel floor. Missing body/trousers intersection outputs are false checks; complete records with failed checks exit nonzero. Root-foot movement ranges are descriptive and do not replace unchanged-leg evidence and video inspection.

The original complete-floor surface/ray gate, clip/video inspection, all-clothing checks, authoritative inventory lifecycle and MP coverage are not implemented here. The floor metric here is only the calibrated tire support against model floor Y=.008, using final rendered matrices. Probe errors, absent agents, empty outputs, topology mismatch and missing model/bone inputs must remain unverified/failing evidence, never waived by a completion marker. Legacy records include genuine male Run-stop overreach; this port does not change or bless that behavior.
