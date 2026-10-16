# Animal trailer native regression intake

[Development](../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../README.md)

Self-contained fixture sources for three B42.21 multiplayer failures. The common runner registers this contribution through `tools/queue_checks/adapters/auxiliary.py` and keeps the shared process lifecycle. `build.py` only compiles/stages test mods; `verify.py` only reads completed run logs. Neither launches a server or client.

This fixture targets B42.21 with ZombieBuddy 2.3.4 and one client plus a dedicated server. SP, RU, Windows/Linux, physical input, WAN and existing saves are unsupported/unverified. Use fresh disposable saves only; never add these test mods to the production selection.

## Prepare offline

From the repository root, set `ANIMAL_GAME` to the directory containing your installed `projectzomboid.jar` and `ZombieBuddy.jar`, and `ANIMAL_JDK` to a JDK 25+ home. The game runtime alone cannot compile Java. `ANIMAL_PATCH` must point to your locally built `PZToolkitJavaPatches.jar` (build with `python3 JavaPatches/build.py --game "$ANIMAL_GAME" --jdk "$ANIMAL_JDK"`, without `--check`). Python 3.10+ and the standard library suffice.

```sh
ANIMAL_RUN=$(mktemp -d)
python3 tests/native_queue/contributions/animal-trailer/build.py \
  --game "$ANIMAL_GAME" --jdk "$ANIMAL_JDK" --patch-jar "$ANIMAL_PATCH" \
  --scenario combined --output "$ANIMAL_RUN/fixtures"
python3 -m unittest discover \
  -s tests/native_queue/contributions/animal-trailer -p 'test_*.py'
```

PowerShell: use `py -3`, `$env:ANIMAL_GAME`, `$env:ANIMAL_JDK`, `$env:ANIMAL_PATCH` and a new temporary output path. All CLI paths are explicit. The output must not exist; the builder refuses to merge into a profile. A failed build can leave this new disposable output for inspection. It validates three exact engine class hashes, compiles Java for release 17, and parses the generated Lua with stock Kahlua without executing it. No game, Workshop files, saves, profiles, credentials or JARs are stored in Git.

Output contains `mods/` and `runtime-manifest.json` with ordered helper IDs and per-JAR hashes. All Java dependencies are externally supplied. The patch JAR is a compile dependency; it is **not copied or enabled automatically**, allowing the equipment negative control to run without it.

## Native runner handoff

The runner must provide the following. No native run is needed merely to import this contribution.

- Acquire the existing shared native-launch guard before launching, and stop only processes owned by this run. Use isolated server and client cachedirs, never a copied live profile/save. Keep Steam disabled for the original localhost scenario.
- Apply `manifest.json.runtime`: Muldraugh map, fresh spawn `10835,10144,0`, zombies disabled (`Zombies=6`), `DoLuaChecksum=true`, `PauseEmpty=true`, default ports 17463/17464. Ports may change consistently; the abandoned 17473 UDP-proxy experiment is not part of this fixture.
- Copy staged mods to both isolated caches and enable the same helper order from `runtime-manifest.json` after `ZombieBuddy` and any chosen production patches. `AnimalReplayProbe` also needs `PZToolkitJavaPatches` loaded. Do not enable staged helpers in unrelated runs.
- Start ZombieBuddy's actual Java loader in **both** processes. Approve the exact generated helper JARs only in that run's isolated loader configuration; generated hashes are supplied for this purpose. The builder creates no approval file. For timer-fixed cases supply externally installed Workshop 3801615436 / `AnimalTrailerSyncMPFix` v1.3, tested hash in the manifest. No third-party code is bundled here.
- Enforce `-novoip` and `voiceEnable=false` in both processes, and check that recording remains uninitialized. The shared launcher owns Cocoa first-thread/display readiness, first-run menus and loading-state handling. This contribution deliberately contains no second platform launcher.
- The runner may connect the client itself. Alternatively, before menu entry inject a `connect` table into generated `AnimalTrailerFixtureConfig`: `{host="127.0.0.1", port=<chosen port>, username=<test account>, password=<runtime credential>}`. Set this identically on disk in both caches to preserve Lua checksums; never commit the generated file. With `connect=nil`, the fixture does not initiate a connection. The shared config is loaded before role-specific Lua.
- The fixture seeds two healthy tame hens and a chick, waits for the trailer ID and optional 8500 ms timer window, calls the real `ISVehicleAnimalUI.onGrabAnimal`, equips a real baseball bat before case 2, verifies exact animals after 9000 ms, then uses native inventory Drop and checks after 7000 ms. These are observation windows, not shortened action durations. Preserve callback bodies and defaults; a missing result or timeout is failure, not permission to shorten actions or fabricate a pass. Original readiness/client budgets: 120/180 seconds, recorded in the manifest.

## Scenarios and criteria

| `--scenario` | Helper(s) | Production setup | Pass condition |
|---|---|---|---|
| `equipment` | AnimalHandsRace | Fixed: Java Patches >=0.1.5; negative control: omit it | Real Equip processed before the real animal grant, then three exact held animals and live drops; negative control instead proves animals stranded in both inventories with empty hands |
| `ghost` | AnimalReplayProbe | Java Patches >=0.1.5 | First held animal proves baseline ghost with only reconciliation temporarily disabled, then real woven decoder repairs it on repeated location-3 snapshots without changing item/animal IDs, hands, neighbor count or capacity; all three native drops succeed |
| `timer` | AnimalTimerProbe | Java Patches >=0.1.5 for stable grabs; compare third-party timer mod absent/present | Direct periodic native sends target exactly the three seeded online IDs: baseline `[0,0,N]`, fixed `[N,N,N]`, `N>0`; all three real grabs/drops succeed |
| `combined` | AnimalHandsRace + AnimalTimerProbe | Same production setup as timer | Both controlled grant ordering and timer criteria, with three successful native grabs/drops |

Example result check for the combined fixed run:

```sh
python3 tests/native_queue/contributions/animal-trailer/verify.py \
  --server-log "$ANIMAL_RUN/server-launch.log" \
  --client-log "$ANIMAL_RUN/client-launch.log" --scenario combined
```

Use `--timer starved` for a timer/combined run without `AnimalTrailerSyncMPFix`. Use `--scenario equipment --hands missing` for the vanilla equipment negative control. A missing control must still finish all three real attempts and inventory/ground audits. `verify.py` rejects incomplete runs, wrong identities, missing native drops, failed grant-order coverage and timer counts for unrelated animals. Unit tests use synthetic log strings only to test this checker; they are not native-game evidence.

## Reproduced problems and gotchas

- **Empty hands:** Equip and animal grant use different ordering channels. An early Equip cannot find the inventory item, returns from parsing with a secondary-status byte unread and echoes empty/old hands. The server then clears the newly granted animal. The controlled negative case must preserve exact animals in both inventories and verify no matching ground animals/items. Java Patches 0.1.5 suppresses only this incomplete local acknowledgement. Spontaneous actual ground drops, null-item decoding and a delayed `PlayerDropHeldItemsPacket` are separate unproven causes.
- **Ghost membership:** late location 2 adds the held animal back to the trailer; vanilla locations 0/1/3 omit symmetric removal. The scenario requires authoritative location-3 replay to repair the ghost with Java Patches 0.1.4+, preserving identities and capacity. The original and production-woven decoder controls use separate JVMs; the runtime replay keeps production patches enabled. Use disposable saves only.
- **Timer:** one `updateAnimal.Check()` inside the reverse vehicle animal loop consumes the interval for only the last animal. The timer criterion uses an 8.5-second observation window: direct-send counts must be `[0,0,N]` without and `[N,N,N]` with `AnimalTrailerSyncMPFix` 1.3, for `N>0`. It complements the client fixes; it does not repair unloading, corpses or already lost animals. Count only direct trailer sends, excluding nested `IsoAnimal.update` sends; retain the direct-caller filter in `java/timer/Main.java`.
- The packet singleton is reused: `AnimalHandsRace` copies decoded fields before deferring, leaves native handlers/data intact, and releases via the original handler after actual Equip processing. Keep both strict `ReadEquip` hook signatures `(ByteBufferReader, IConnection)`; a signature mismatch can leave the probe inactive. Logs named `EQUIP_CLIENT_ECHO` mark the handler exit; with the production fix, the incomplete acknowledgement itself is suppressed. Terminal audit waits for the actual equip-triggered release and the full post-action observation window. A missing echo hits a bounded failure; the fixture never manually releases a delayed grant.
- Standalone examples use minimal fixture dependencies. The common runner also accepts a locked selected pack; loaded mods do not gain behavioral coverage from loading. Unmodified Workshop timer-mod folders may emit harmless missing `AnimSets`/`actiongroups` directory warnings; only an `ACTIVE 1.3` server message plus observed sends proves the tested path.
- Grouped cleanup returns the actor through native `GameServer.sendTeleport`, then requires client arrival and a separate authoritative server-position ACK before exact owned-resource cleanup. Gameplay grabs use native walking; cleanup does not rely on pathfinding success near walls. Sound and VOIP stay disabled by the common runner.
- Existing engine-level checks remain in `JavaPatches/tests/zombie/characters/AnimalChecks.java` and `JavaPatches/tests/zombie/network/packets/EquipmentChecks.java`; do not duplicate them into this contribution. The common adapter stages these sources and invokes the retained verifier; current evidence is recorded in each run report.
