# Fridge negative-cache experiment

Development-only source experiment for the selected `NicksTurnOffFridges` mod.
It does not modify Workshop, shipped Toolkit, installed game files or profiles.

The exact upstream `TOF_Light.lua` builds a string coordinate key for every square
in each player's 31 x 31 sweep, including cached negative hits. This candidate
replaces that one membership lookup/insertion with nested numeric `z`, `x`, `y`
tables. It changes neither the sweep nor its callbacks, radius, 120-tick interval,
LoadChunk nudge, fridge recognition, auto-unplug poll, light work or insertion rule.
It deliberately preserves the upstream permanent negative cache, including its
existing behavior when a fridge appears on a previously cached empty square.
Native `math.floor` uses `BoxedStaticValues.toDouble`, which canonicalizes signed
zero before membership. Its native bytecode is included in the input receipt.
No bounded coordinate packing, eviction or cross-coordinate cache approximation
is used. Sweeps floor player coordinates and enumerate integral square coordinates;
numeric table membership is exact across the game's signed integer axes/elevations.

## Run

Use the directory containing the external B42.21 `projectzomboid.jar`, JDK 25,
a frozen upstream mod directory containing `common/media/lua`, and a new disposable
output directory:

```sh
python3 tests/chunk_integration/fridge_cache/run.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" --upstream "$PZ_FRIDGE_SOURCE" \
  --output "$PZ_FRIDGE_RESULTS"
```

Add `--measure` to run five alternating baseline/candidate JVM pairs. The timing
phase acquires the existing exclusive resource admission slot, with bounded wait;
on macOS run outside the sandbox for ordinary host inspection. Each JVM has a
256 MiB heap, runs one measurement thread, and opens no window. Defaults are
50 cross-case priming rounds, then 50 warmup and five measured rounds of 100 sweeps in each case. Workloads and forks
are bounded by the runner; `--resource-wait` may be 0..900 seconds. Each subprocess
has a 240-second deadline. Do not overlap compilation or other timing experiments
with an admitted measurement. Baseline/candidate correctness runs happen first,
outside admission.

The runner rejects a changed light-source digest or a nonunique replacement,
copies all three full upstream Core/Light/Client files and the real native
`stdlib.lua` into its isolated output, and compiles them with the game's actual
Kahlua compiler. No copied sweep implementation or Lua 5.x substitute is measured.
The native Java classes are loaded directly from the external game JAR. The source,
Kahlua class, native JAR, stdlib and compiled Lua bytecode hashes are retained in
`input-receipt.json` / `result.json`; JVM logs and every measurement row remain
available, including failed/unqualified attempts.

## Checks and measurement scope

World access is explicitly doubled. Native Kahlua executes the full upstream
callback and the actual Core recognition/Client auto-poll functions. The semantic
fixture checks first periodic sweep, repeated warm hits, unchanged stale negatives,
separate signed elevations/axes and canonical signed zero, unloaded retries, load nudges on successive ticks,
periodic counter reset, repeated fridge visits and overlapping split-screen players.
It does not launch a native world or simulate a real object-stream race.

Measured cases each execute actual 961-coordinate sweeps through `OnTick`:

- `warm`: stationary player, all loaded empty negatives already cached.
- `cold`: 100 disjoint horizontal windows, all loaded empty; every visited coordinate new.
- `mixed`: stationary 1/7 unloaded, sparse plugged fridges and ordinary objects;
  real Core/Client execute on the fridge double, with automatic policy disabled.
- `moving`: advance one tile per sweep; overlap stays cached and one 31-square
  frontier enters each time (first sweep is cold).

Each measured round starts in a fresh environment, with case-specific priming
outside its timing window. Consumed world lookup/object counts must match across
all paired runs. Wall time, current-thread CPU and allocated bytes are reported
per sweep and retained per round/fork. Timed windows and JIT/GC/safepoint logs are
retained; relevant Kahlua/harness compilation inside a measured window rejects
qualification. GC/off-CPU noise remains visible in the per-fork differences.

These are the Lua callback's synthetic workloads, not native `getSquare` world,
object/light costs or event-dispatch/render costs. A warm-hit sweep's CPU/allocation
change can be attributed to its unchanged 961 lookups plus the cache representation;
real miss costs can differ. Do not turn this into an FPS or driving-stutter claim.
The cold moving pattern intentionally has bounded sample size; it does not establish
long-session retention. Numeric nested caches also retain plane/column tables.

## Integration limit

`noFridge`, `sweepSquare`, `sweep` and both registered handlers are private locals.
There is no supported public hook that replaces this cache. Wrapping `OnTick` or
adding another callback cannot remove the original work. Do not install a runtime
upvalue rewrite or source replacement on the strength of this fixture. A safe
follow-up is an upstream change, or an explicitly owned/vendored mod source with
license/update handling and startup digest guards, followed by full-pack SP and
menu-Host qualification. This fixture supplies no runtime patch or installation.

## Current research verdict

The final macOS five-pair batch is **unqualified**. All ten measured JVMs and both
initial correctness JVMs passed the semantic fixture (27 assertions per invocation)
and their consumed workload counters matched. The strict compilation gate still
flagged two timestamps with the full 50-round cross-case/per-case warmup:

- Pair 0 candidate, `warm` round 3: `FridgeCacheCheck.load` at 11785 ms,
  matching the rounded end of its 11763..11785 ms window.
- Pair 1 candidate, `warm` round 1: `J2SEPlatform.<init>` at 11255 ms,
  matching the rounded end of its 11234..11255 ms window.

These setup methods are called outside the measured loop. Millisecond boundaries
cannot resolve whether the logged compilation belongs just after that loop; the
conservative gate remains unchanged and the full batch remains rejected. Pairs
2, 3 and 4 have no flagged relevant compilation in any of their 120 windows. All
stock windows and the other candidate windows are also free of flagged events.
Earlier rejected/partial attempts remain available separately from the final batch.

For triage only, medians across the three clean pairs show approximately
0.10..0.11 ms less thread CPU per 961-square sweep in the four synthetic patterns.
Their allocated-byte reductions are approximately 245..284 kB per sweep. This is
useful cache-path evidence, but it does not qualify the complete five-pair batch or
establish native world cost, actual callback frequency, frame time or FPS benefit.
The potential absolute saving and the private-handler integration limit do not
justify an unsafe runtime rewrite. Keep this as an upstream/source-level candidate.
Any future timing qualification should resolve the setup/measurement timestamp
boundary explicitly while retaining the compilation gate.
