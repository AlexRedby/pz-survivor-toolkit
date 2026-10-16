# Crafting-plan native fixture intake

[Development](../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../README.md)

This B42.21 contribution is **intake only**, with no common catalog entry and no current native verification claim. It does not include the planner implementation, game/Workshop files, Java binaries, profiles, worlds or generated outputs. The parameterized scenarios cover crafting chains/cancellation/shared inputs, UI layout and cleanup, and ingredient alternatives.
`manifest.json` records source fingerprints, scenario files, dependencies,
parameters, output markers and evidence limits. The alternatives fixture comes
from the final fixed implementation, not the earlier fixture that deliberately
asserted the auto-fill bug as current behavior.

## No-game validation

From the repository root, with Python 3 and LuaJIT or Lua 5.1 on PATH:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/native_queue/contributions/crafting-plans/check.py
```

This stages only fixture files in temporary directories, checks all three roles
have identical mod bytes, verifies configuration/collision guards, compiles Lua
and counts registered stages. It does not execute game callbacks or stage bodies.
Registration success is not recipe, UI or multiplayer verification.

## Preparation for a later native run

The checkout must contain Toolkit's `CraftPlanner`, `CraftChainRecipes`,
`CraftChains` and operation-aware `ActionQueue`, plus Wishlist and the UI
integrations in the manifest. This contribution alone does not supply those
features. Use the current selected INI and resolve dependencies through the
common native tooling; the current selected INI defines the mod set.
Do not merge this helper with another active fixture: both claim the test actors,
modify their inventories and install native action hooks.

Use three disposable caches and a fresh world for **each** scenario. The common
runner must own the matching game/product/Workshop snapshots, port checks,
launcher, process lifecycle and evidence collection. With `TEST_CACHE`,
`TEST_HOST`, `TEST_PORT` and `CRAFT_TEST_PASSWORD` already supplied at runtime:

```sh
python3 tests/native_queue/contributions/crafting-plans/prepare.py "$TEST_CACHE/client1" \
  --user client1 --scenario alternatives --host "$TEST_HOST" --port "$TEST_PORT" \
  --password-env CRAFT_TEST_PASSWORD
```

Repeat for `client2` and `server`, changing only cache/actor. `prepare.py` installs
one scenario's client and server files as the `CraftPlanTest` helper and writes
five data lines to `<cache>/Lua/craft-fixture.txt` with private permissions. It
refuses an existing helper/config and never copies game/product mods, alters a
server INI, downloads, launches or compiles Java. The password stays out of argv
and Git. Per-role parameters live outside the mod tree to preserve Lua checksums.

Enable `CraftPlanTest` after the product mods in all three caches' selection and
in server `Mods=`. Apply the server/sandbox settings in the manifest; use the
supplied game port and the adjacent UDP port. Run only an isolated local server,
with voice disabled and client `-novoip`. Fixed accounts `client1` and `client2`
use the runtime password, languages EN and RU respectively. The setup adds items,
Carving XP and a native surface/container; it must never run in a real save.

Reuse the common `tests/native_queue/support/ToolkitSmokeLauncher.java` and
preflight once integrated; keep installation paths and process ownership in the
common runner. An awake desktop and working native libraries
are required; changing an INI alone does not prove that the renderer adopted the
requested size. On macOS, a tiling window manager may resize test windows.

The common queue runner uses different case selectors/events. These helpers
cannot be enabled merely by adding a suite name. Integration must dispatch the
selected scenario, provide its parameter file and interpret its marker contract.
Do not mark it ready until the transferred path has a fresh native run.

## Acceptance and limits

Require one `COMPLETE checks=N failures=0` from **each** client, matching the
manifest and its `EXPECTED` marker. Any `[CRAFT_TEST] FAIL`, missing completion,
unexpected process exit or gameplay Lua exception fails the run. Completion
alone is insufficient: `crafting` needs both cancellation/chain server checks
and one shared-log conversion; `alternatives` needs all three server verification
phases for both clients. Compare the exact marker names in the manifest.

For `ui`, require preview/fallback render markers, all scrollbar-bound checks,
owner guards, and actual Start/cancellation markers; inspect screenshots in both
languages. That scenario cancels its waiting crafts and does **not** demonstrate
output creation. For full-set Java configurations, retain the common loader and
transformation checks. Verify current game, product and Workshop APIs before accepting a run.

SP, Windows/Linux, physical mouse/keyboard/controller navigation, split-screen, respawn and WAN behavior are unverified. Crafting durations are native. Book cancellation
uses shortened reading time; the fixture is not a reading-performance test.
The entity-window guard uses a fake owner around a real NC cell, not a newly
placed workbench. No product behavior is patched to force test results.

## Reproduced problems and useful boundaries

- **Kahlua lacks `next`.** The first native chain run failed inside `spec` at
  `next(result.outputs)`. Ordinary Lua-only mocks had not exposed it. Preserve
  native registration/execution gates and do not infer Kahlua APIs from Lua 5.1.
- **Auto-fill is not picker intent.** NC enables manual mode and fills
  `getManualInputsFor` automatically. Pinning those IDs blocked a second log or
  branch craft and prevented producing a missing handle. The final alternatives
  scenario checks repeated quantities, explicit native picks and Auto recovery.
- **Picker state survives a visual close.** An earlier alternatives run could
  not reopen the tool picker after a plan preview. Clear the native show/filter
  flags as well as the panel. The retained scenario opens the picker repeatedly.
- **Manual off/on and unavailable intermediate choices need real resets.**
  Track `onManualSelectChanged(false)`; remove an intermediate override on Auto
  instead of retaining a false entry for an unavailable recipe. The native
  fixture covers the mode reset and missing material; the unavailable-producer
  edge itself was a Lua UI regression, not a separately manufactured native case.
- **Retained-tool reservation is order-sensitive.** Reserving a final tool too
  early originally blocked a prerequisite that needed the same tool. Invocation
  reservations allow nested keep-use without consuming that reservation. This
  diagnosis came from planner regressions; the native fixtures do not construct
  every abstract tool-dependency shape. Preferred IDs remain soft on conflicts.
- **Lua and engine list geometry can diverge.** An earlier UI run reported
  `preview wheel did not scroll`; retain actual native viewport/scrollbar bounds,
  rendered-frame waits, footer checks and owner cleanup. Do not replace these
  assertions with a Lua-only height comparison.
- **Server authority matters.** Client queue completion does not prove item
  conservation. The chain and alternatives fixtures check server output counts,
  original source IDs and retained tools. The shared-log race expects exactly
  one conversion globally; it does not prescribe which player wins.
- **Fixture XP direction matters.** Use the server XP packet for the Carving
  grant (`addXpNoMultiplier`); the old comment records that `SyncXp` sends in the
  opposite direction. Wait for the client skill level before planning.
