# Crafting-plan native fixture

[Development](../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../README.md)

The common `crafting-plans` adapter stages the B42.21 client/server scenarios and verifies exact stage labels and authority receipts. Dependencies are supplied locally; no game/Workshop files, binaries, worlds or generated outputs are distributed. Per-run reports record current verification separately from registration.

`crafting` covers real chains, waiting cancellation, shared-log competition and
classic/NC controls. `ui` covers layout, icons/counts, scrolling, resizing,
quantity review, cleanup and cancellation. `alternatives` checks the native
picker, Auto recovery, quantities, choices and selected-source crafting.

`manifest.json` records source fingerprints, scenario files, dependencies,
parameters, output markers and evidence limits. The alternatives fixture checks the current Auto/material-picker behavior.

## No-game validation

From the repository root, with Python 3 and LuaJIT or Lua 5.1 on PATH:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/native_queue/contributions/crafting-plans/check.py
```

This stages only fixture files in temporary directories, checks all three roles
have identical mod bytes, verifies configuration/collision guards, compiles Lua
and counts registered stages. It does not execute game callbacks or stage bodies.
Registration success is not recipe, UI or multiplayer verification.

## Fixture preparation

The shared adapter invokes `prepare.py` for each role to stage the selected case
and its private runtime parameters. The helper can also be run directly to inspect
staging; it creates no game profile and launches no process. Keep its generated
helper/cache and credentials outside Git. For example:

```sh
python3 tests/native_queue/contributions/crafting-plans/prepare.py "$TEST_CACHE/client1" \
  --user client1 --scenario alternatives --host "$TEST_HOST" --port "$TEST_PORT" \
  --password-env CRAFT_TEST_PASSWORD
```

The helper rejects existing fixture/config files and keeps per-role parameters
outside the mod tree to preserve Lua checksums. The adapter applies the manifest
settings and inserts the helper into disposable role caches.

The shared runner owns the launcher, preflight, process handling and evidence
collection.

Choose one case or an ordered subset with `--cases ui,crafting,alternatives` in
a fresh two-client MP lifecycle. The adapter runs selected cases in that order
with joint cleanup between them. The fixture requires the Toolkit operation API, so `--mode native` is
unsupported. See the [runner guide](../../README.md) for current launch commands
and report interpretation.

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
