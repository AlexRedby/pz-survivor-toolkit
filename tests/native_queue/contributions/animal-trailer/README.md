# Animal trailer multiplayer fixture

[Development](../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../README.md)

Fixture sources for B42.21 multiplayer equipment ordering, trailer membership and animal timer checks. The common adapter owns the native run; `build.py` compiles/stages helpers and `verify.py` checks completed logs. Neither helper launches a game process.

This fixture targets B42.21 with ZombieBuddy 2.3.4 and one client plus a dedicated server. SP, RU, Windows/Linux, physical input, WAN and existing saves are unsupported/unverified. Use fresh disposable saves only; never add these test mods to the production selection.

## Prepare offline

From the repository root, set `ANIMAL_GAME` to the directory containing your installed `projectzomboid.jar` and `ZombieBuddy.jar`, and `ANIMAL_JDK` to a JDK 25+ home. The game runtime alone cannot compile Java. Building the production patch also requires the [Kotlin 2.4.21 toolchain](../../../../docs/development/JAVA.md#java-development); set `KOTLIN_HOME` or pass `--kotlin-home` to that build. The fixture builder itself compiles only Java helpers against the complete patch JAR, whose private Kotlin runtime is already bundled. `ANIMAL_PATCH` must point to your locally built `PZToolkitJavaPatches.jar` (build with `python3 JavaPatches/build.py --game "$ANIMAL_GAME" --jdk "$ANIMAL_JDK"`, without `--check`). Python 3.10+ and the standard library suffice.

```sh
ANIMAL_RUN=$(mktemp -d)
python3 tests/native_queue/contributions/animal-trailer/build.py \
  --game "$ANIMAL_GAME" --jdk "$ANIMAL_JDK" --patch-jar "$ANIMAL_PATCH" \
  --scenario combined --output "$ANIMAL_RUN/fixtures"
python3 -m unittest discover \
  -s tests/native_queue/contributions/animal-trailer -p 'test_*.py'
```

PowerShell: use `py -3`, `$env:ANIMAL_GAME`, `$env:ANIMAL_JDK`, `$env:ANIMAL_PATCH` and a new temporary output path. All CLI paths are explicit. The output must not exist; the builder refuses to merge into a profile. A failed build can leave this new disposable output for inspection. It validates three exact engine class hashes, compiles Java for release 25, and parses the generated Lua with stock Kahlua without executing it. No game, Workshop files, saves, profiles, credentials or JARs are stored in Git.

Output contains `mods/` and `runtime-manifest.json` with ordered helper IDs and per-JAR hashes. All Java dependencies are externally supplied. The patch JAR is a compile dependency; it is **not copied or enabled automatically**, allowing the equipment negative control to run without it.

## Fixture setup contract

- The manifest supplies the Muldraugh spawn, sandbox, default ports and helper order. The adapter stages the helpers after `ZombieBuddy` and selected production patches; `AnimalReplayProbe` also requires `PZToolkitJavaPatches`. For timer-fixed cases, supply the installed Workshop 3801615436 / `AnimalTrailerSyncMPFix` v1.3 with the hash recorded in the manifest.
- Before each case, the server selects a loaded free square at the trailer's actual `AnimalEntry` and issues native teleport. The client must observe that square and reachable entry; the server separately observes arrival before sending `Fixture`. Setup fails after 30 seconds or if no safe nearby square exists. `AnimalSessionProbe` is therefore staged for single cases too. The verifier requires both start receipts and all three grabs within 1.6 tiles per axis of the entry.
- The fixture seeds two healthy tame hens and a chick, waits for the trailer ID and optional 8500 ms timer window, calls the real `ISVehicleAnimalUI.onGrabAnimal`, equips a real baseball bat before case 2, verifies exact animals after 9000 ms, then uses native inventory Drop and checks after 7000 ms. These are observation windows, not shortened action durations. Preserve callback bodies and defaults; a missing result or timeout is failure. Readiness/client budgets are recorded in the manifest.

## Scenarios and criteria

| `--scenario` | Helper(s) | Production setup | Pass condition |
|---|---|---|---|
| `equipment` | AnimalHandsRace | Fixed: Java Patches >=0.1.5; negative control: omit it | Real Equip processed before the real animal grant, then three exact held animals and live drops; negative control instead proves animals stranded in both inventories with empty hands |
| `ghost` | AnimalReplayProbe | Java Patches >=0.1.5 | Separate headless JVMs check the original and production-woven decoders. Live replay keeps production patches enabled and repairs membership on repeated location-3 snapshots without changing item/animal IDs, hands, neighbor count or capacity; all three native drops succeed |
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

- **Empty hands:** Equip and animal grant use different ordering channels. An early Equip cannot find the inventory item, returns from parsing with a secondary-status byte unread and echoes empty/old hands. The server then clears the newly granted animal. The controlled negative case requires an empty primary hand; after the occupied-hands grab the exact original bat remains in the secondary hand, including the third grab. Both sides must agree on these hand IDs, retain every already granted animal with its original inventory item ID, and match the native grant-release IDs. Each audit checks all 121 loaded squares in the local 11x11 area for matching ground animals/items; it does not prove absence across the whole map. Java Patches 0.1.5 suppresses only this incomplete local acknowledgement. Spontaneous actual ground drops, null-item decoding and a delayed `PlayerDropHeldItemsPacket` are separate unproven causes.
- **Ghost membership:** late location 2 adds the held animal back to the trailer; vanilla locations 0/1/3 omit symmetric removal. The scenario requires authoritative location-3 replay to repair the ghost with Java Patches 0.1.4+, preserving identities and capacity. The original and production-woven decoder controls use separate JVMs; the runtime replay keeps production patches enabled. Use disposable saves only.
- **Timer:** one `updateAnimal.Check()` inside the reverse vehicle animal loop consumes the interval for only the last animal. The timer criterion uses an 8.5-second observation window: direct-send counts must be `[0,0,N]` without and `[N,N,N]` with `AnimalTrailerSyncMPFix` 1.3, for `N>0`. It complements the client fixes; it does not repair unloading, corpses or already lost animals. Count only direct trailer sends, excluding nested `IsoAnimal.update` sends; retain the direct-caller filter in `java/timer/Main.java`.
- The packet singleton is reused: `AnimalHandsRace` copies decoded fields before deferring, leaves native handlers/data intact, and releases via the original handler after actual Equip processing. Keep both strict `ReadEquip` hook signatures `(ByteBufferReader, IConnection)`; a signature mismatch can leave the probe inactive. Logs named `EQUIP_CLIENT_ECHO` mark the handler exit; with the production fix, the incomplete acknowledgement itself is suppressed. Terminal audit waits for the actual equip-triggered release and the full post-action observation window. A missing echo hits a bounded failure; the fixture never manually releases a delayed grant.
- Loading additional mods does not establish behavioral coverage. Unmodified Workshop timer-mod folders may emit harmless missing `AnimSets`/`actiongroups` directory warnings; only an `ACTIVE 1.3` server message plus observed sends proves the tested path.
- Grouped cleanup returns the actor through native `GameServer.sendTeleport`, then requires client arrival and a separate authoritative server-position ACK before exact owned-resource cleanup. Gameplay grabs keep the native adjacent walking/action path; cleanup does not rely on pathfinding success near walls.
- Existing engine-level checks remain in `JavaPatches/tests/zombie/characters/AnimalChecks.kt` and `JavaPatches/tests/zombie/network/packets/EquipmentChecks.kt`; do not duplicate them into this contribution. The common adapter stages these sources and invokes the retained verifier; current evidence is recorded in each run report.
