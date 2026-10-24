# Cart animation authoring

[Development](../DEVELOPMENT.md)

Prepare, edit and export cart clips and clearance curves. Run commands from the repository root; generated Blender workspaces stay outside mod packages.

- [Cart animation authoring in Blender](#cart-animation-authoring-in-blender)

## Cart animation authoring in Blender

Start from a clone of this repository and install these external prerequisites:

- Python 3.10+ for the launcher; no pip packages are needed for this workflow.
- Blender 4.5 LTS, including its bundled Python, `bpy` and `mathutils`.
- JDK 25+ with both `java` and `javac` for the native export check.
- The supported Project Zomboid B42.21 installation. Its Java directory must contain `projectzomboid.jar`, the native importer libraries, `media/anims_X/Bob/Bob_Idle.x` and `media/models_X/Skinned/{MaleBody,FemaleBody}.x`.
- For the wooden pickup's cart reference, the installed Steam Workshop item **3689975894**, SaucedWheelbarrow. The required file is `mods/SaucedWheelbarrow/42/media/models_X/weapons/2handed/Wheelbarrow_wood.fbx` inside that item's directory. An existing local copy can be selected with `--cart-fbx`.

All project scripts, native check helpers, presets and editable pose sources are in Git under `tools/`, `tests/` and `assets/animations/`. Blender, the JDK, game files and Workshop models are external installations. The `.blend` scene is generated from those inputs; no pre-existing scene, Codex installation, account configuration or agent investigation files are required.

On macOS the launcher discovers Blender in `~/Applications` or `/Applications`, the standard Steam game path and the installed JDK. From the clone's root, run:

```sh
python3 tools/cart_blender.py prepare --clip wood_cart_pickup
python3 tools/cart_blender.py edit build/blender/wood_cart_pickup
python3 tools/cart_blender.py export build/blender/wood_cart_pickup
python3 tools/cart_blender.py render build/blender/wood_cart_pickup --frame 20
```

For nonstandard installations, pass paths when preparing the workspace:

```sh
python3 tools/cart_blender.py prepare --clip wood_cart_pickup \
  --blender /path/to/Blender.app --jdk /path/to/jdk-25 \
  --game /path/to/game-Java \
  --cart-fbx /path/to/Wheelbarrow_wood.fbx
```

`--blender` also accepts the Blender executable directly. `--workshop /path/to/steamapps/workshop/content/108600` selects a different Steam library instead of a single FBX. Windows users can use `py -3` in place of `python3` and pass their installed executable/JDK/game paths; verification here was performed on macOS.

Preparation creates `build/blender/wood_cart_pickup` containing `scene.blend`, its configuration and macOS double-click launchers. It never replaces an existing workspace; use `--output` for another version. The wooden pickup preset includes the measured playback duration and a calibrated cart reference. The other supplied source clips are `metal_cart_pickup`, `shopping_cart_pickup`, `wood_cart_brace`, `wood_cart_pivot_left` and `wood_cart_pivot_right`; use `--clip NAME --duration SECONDS` with their actual playback duration. These have a live body without a cart reference. Add `--female` to prepare the native female body.

The body follows pose edits immediately through saved Blender constraints and linear skinning; reopening the scene does not require script auto-run. The editable `CartClip` skeleton is separate from the hidden bind skeleton. The prepared viewport starts in Pose Mode with Auto Key enabled. Space plays the clip; the Dope Sheet edits key timing. Open through the launcher to load the **PZ Cart** sidebar and its **Save + Export to PZ** button. A direct double-click on `.blend` retains the live mesh but does not register the session-only sidebar.

Exports retain added and moved keys and create a new `exports/` snapshot with pose JSON, native `.x`, logs and `report.json`. Native PZ import/FK must reproduce the scene's keys and intermediate frames within the matrix tolerance before the result is reported as passing. Bezier curves or authoring constraints require the sidebar's bake option or `export --bake-fps 60`; the exporter increases sampling up to 240 fps when the native checker detects an approximation error, and fails if that still exceeds the tolerance. The low-level `cart_clip_blender.py export` still defaults to original timestamps; the workspace launcher uses authored key timing.

`build/blender/` contains generated scenes, local absolute paths, imported game/Workshop geometry and export snapshots. It is ignored by Git and excluded from mod packaging. A new clone recreates it with `prepare`; after moving the clone or changing machines, prepare a new workspace rather than copying the old configuration. Preserve any hand-edited scene separately before removing an old workspace. Export does not replace repository animation sources or install anything into the game. The cart is an authoring reference: runtime hand IK, ground adaptation, clothing, interruptions and multiplayer transitions still require PZ checks. Offline verification was performed on macOS with Blender 4.5.9.

Run the fast parser/bridge checks with `python3 -m unittest discover -s tests -p 'test_cart*blender*.py'`. To exercise actual edits, key insertion/retiming, reload and the sidebar's native export, run Blender with `--background --python-exit-code 1 --python tests/blender_cart_edit_check.py -- WORKSPACE`; this creates a separate `verification/` scene and leaves the original scene unchanged.

### Replay an inventory-equip transition

Inventory-menu equip uses the native inventory animation, not the ground-pickup clip. To inspect its outgoing blend, capture the SP `wooden_cart_motion/approach` scenario with `cart_entry_contact_repro: true` and explicit `cart_scenes: ["container-equip"]` (or include `"wrong-side"` for a separate ground-approach control). The option records native Walk before the actual inventory callback, worn male baggy jeans, full cargo, full influencing bone palettes and a one-second held tail. Use the native runner's explicit dependency paths and isolated settings; source snapshots and geometry reports do not establish every rendered frame.

The replay and curve-authoring tools run inside Blender. `BLENDER` below means its installed executable; `GAME` is the folder containing `projectzomboid.jar`, and `CART_FBX` is the installed wooden-wheelbarrow model. Replace `PROFILE` and `LOG` with the captured client profile and its `console.txt`:

```sh
"$BLENDER" --background --python-exit-code 1 --python tools/cart_blender_replay.py -- \
  --profile "$PROFILE" --log "$LOG" --game "$GAME" --cart-fbx "$CART_FBX" \
  --output build/blender/inventory-replay
"$BLENDER" --background --python-exit-code 1 --python tools/cart_blender_clearance.py -- \
  prepare build/blender/inventory-replay/replay.blend build/blender/inventory-clearance
"$BLENDER" build/blender/inventory-clearance/authored.blend
```

The replay verifies Blender's evaluated body and actual `Bob_Trousers` mesh against every captured native sample within `2e-5` model units. Unweighted Nub bones are filled from their parents; all 35 influencing native bones remain measured. The saved scene works without script auto-run. Select **Equip clearance envelope** and edit its Y location curve in the Graph Editor. Frames 1..61 represent the retired share of the outgoing inventory animation, rather than scene time. A saved Action constraint evaluates the curve against recorded blend weights, so edits update the cart preview immediately. The preview arms remain recorded; actual runtime IK and closed grip require the game check.

```sh
"$BLENDER" --background --python-exit-code 1 --python tools/cart_blender_clearance.py -- \
  export build/blender/inventory-clearance/authored.blend build/blender/inventory-clearance/export
```

Export creates a new curve JSON, generated Kotlin sampler and approximation report. It checks zero endpoints, forward-only bounds and intermediate samples, increasing sampling until the interpolation error is below `2e-6` model units. To propose a runtime change, review both outputs and update `assets/animations/curves/wood_cart_equip_clearance.json` and `JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartEquipClearanceCurve.kt` together. `tests/test_cart_clearance_curve.py` checks that they agree. Build and test the candidate through the isolated reproducer; exporting or opening the scene does not install or validate gameplay. The current envelope is a rendered cart-placement correction while inventory Loot retires; it does not replace the pickup clip or native legs.

### Recalibrating the held-leg clearance cage

The held wooden-cart fit reads the native render slot's body and supported trousers palettes. Its generated source cage and shaft decomposition are committed in `CartLegClearanceData.kt`; ordinary patch builds need neither Blender nor NumPy. A changed game/Workshop asset hash disables that asset's calibration until it is reviewed and regenerated.

Regeneration requires Python with NumPy, the supported B42.21 game files and the original wooden cart FBX:

```sh
python3 tools/cart_leg_clearance_profile.py --game "$GAME" --mesh "$CART_FBX" \
  --output JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartLegClearanceData.kt
python3 tools/cart_leg_clearance_profile.py --game "$GAME" --mesh "$CART_FBX" \
  --output JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartLegClearanceData.kt --check
```

The generator verifies source identities, skin weights and exact kernel-fan decomposition of the nonconvex closed shaft pieces. Open braces retain their original triangles. The runtime selects the nearest lateral corridor with a 1 mm source-cage margin, rechecks the solved hand pose and refuses a nonzero correction whose calibrated cart vertices leave the existing Walk footprint. Native collision, leg/root motion, packet frequency and the Blender forward envelope remain unchanged. Source-cage regressions and captured matrices do not certify unseen clothing or every GPU-rendered frame; rerun the isolated SP/Host checks after recalibration.
