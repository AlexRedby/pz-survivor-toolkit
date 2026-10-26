# Native loot lookup experiment

This standalone experiment measures one repeated lookup inside B42.21
`ItemPickerJava.getActualSpawnChance`. It is not part of either shipped mod and
does not install anything into the game.

The native method already resolves the original name into an `Item`. Its
`getBaseChance` helper resolves that name again before multiplying `chance` by
`getBaseChanceMultiplier`. The experimental class-file splice substitutes that
multiply and existing multiplier call, using the original local value, including
null. The modifier's separate `Empty` fallback is never used for base chance or
zombie density. There is no cross-call cache, deferred loot, RNG change or new
category calculation. Public helper methods remain unchanged for other callers.

The builder admits one exact native class digest, requires exactly one replaced
call and rejects changed/already transformed input. The runner additionally
pins native resolver, bucket, item and sandbox classes. It does not establish
compatibility with other in-memory instrumentation of those methods.

## Run

Set `PZ_GAME` to the directory containing `projectzomboid.jar` and
`ZombieBuddy.jar`, and `JAVA_HOME` to JDK 25. Supply a new disposable output path:

```sh
python3 tests/chunk_integration/loot_lookup/run.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" --output "$PZ_LOOT_RESULTS"
```

Add `--measure` for five alternating stock/candidate JVM pairs. The timing phase
uses the common exclusive resource admission, including its existing ownership,
FIFO and capacity checks. On macOS, run this phase outside the sandbox so host
probes can operate. It opens no window and does not change the desktop. Do not
overlap the measurement with compilation, packaging or other timing experiments.
The default `--resource-wait` is 900 seconds; a timeout is not permission to bypass
the slot. `--iterations` changes the per-round workload, not its input cases.

The runner snapshots sources, compiles against external native classes, writes a
standalone class overlay, and starts stock/candidate JVMs from an empty working
directory with isolated cache/home paths. Native filesystem initialization is
required before the sandbox constructors. No native script/mod pack is loaded;
the fixtures populate real native buckets and explicitly set native options.

## Evidence and scope

The 59 raw-float-bit vectors cover full-type/module/alias/import lookup, missing
items, distinguishing `Empty` fallbacks, junk, removal lists, density, sandbox
changes, live tag/category mutation, item replacement and floating-point edges.
The benchmark consumes results and compares their checksums, reports wall time,
current-thread CPU and allocations, and retains per-round and paired-fork data.
JIT logs are checked for relevant compilation inside the measured windows.

`result.json` and `input-receipt.json` identify source/native/overlay bytes;
separate logs retain both passing and failed runs. A microbenchmark result only
describes these native calculations on these inputs. It does not prove a driving
frame-time improvement, real generated contents/RNG sequence/callback order,
full-pack instrumentation compatibility, or Host behavior. Those are separate
requirements before any runtime delivery.
