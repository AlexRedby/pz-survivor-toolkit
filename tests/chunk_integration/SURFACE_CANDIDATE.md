# Surface allocation candidate check

This check consumes the external B42.21 game JAR, JDK 25, pinned official optimizer
release ZIP, and bounded-profile manifest. It does not launch the game, install
anything, fetch dependencies, rewrite the profile, or redistribute runtime classes.
Its temporary classpath is deleted after completion. JVM logs and measurements go
only to the requested output directory.

Use `--correctness-only` for a short qualification without CPU or allocation
benchmarks. It runs the false and true branches once each, compares the native
baseline, and returns before allocation-counter setup, warmup or measurement loops:

```sh
python3 tests/chunk_integration/run_surface_candidate.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" \
  --release "$PZOPT_RELEASE" --manifest "$PZOPT_MANIFEST" \
  --output "$PZ_SURFACE_CORRECTNESS_RESULTS" --correctness-only
```

The result records the exact snapshotted Java source digest and input digests;
`rows` and `summary` are empty in this mode. `--forks` does not multiply correctness
runs, and `--batch-compilation` is a separate workflow.

`PZOPT_MANIFEST` must point to the sealed `tests/optimizer_trial/candidate-manifest.json`
supplied by the parent optimizer integration track. This check does not generate
that manifest. Its full canonical digest is pinned in `run_surface_candidate.py`.

```sh
python3 tests/chunk_integration/run_surface_candidate.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" \
  --release "$PZOPT_RELEASE" --manifest "$PZOPT_MANIFEST" \
  --output "$PZ_SURFACE_RESULTS" --forks 3
```

Repeat with `--batch-compilation` and a separate output directory to synchronize
JIT compilation and examine warmed tiered code. Each run starts independent JVMs
for false/true, reverses their order in alternating forks, and records both default
tiered and forced C1 (`-XX:TieredStopAtLevel=1`) results. C1 is a diagnostic condition;
the pinned profile uses `jitMode=tiered`. Each scenario warms for 600,000 operations,
then measures seven rounds of 350,000 operations. Allocation uses the JVM's current
thread allocation counter, not heap occupancy.

`cold` invalidates only the private lazy-cache flag through a VarHandle before each
get. `set` uses the public setter before each get and includes setter cost. `cached`
reads an already initialized container. The empty `set` case gains a Surface entry
on its first operation. Shapes cover empty, one surface entry, all nine surface
properties, and Surface plus 64 unrelated properties. These are focused native
object measurements, not distributions captured from the user's game.

Correctness compares every surface field exposed through nine getters, all three
surface bits, numeric boundaries and malformed values, direction exceptions,
public setter/unset/put/remove/AddProperties/Clear cache behavior, rehashes and
tombstones. Stable vectors also run against stock native PropertyContainer.
Official false/true branches additionally compare invalid alias keys/values and
FREE/REMOVED slots. These deterministic snapshots do not certify concurrent
mutation or chunk/Host behavior.

The release ZIP SHA-256 is
`2bcd0e01a3ac66856fae137ff1dbda66c8397375da781e7a6ed67fe2b9d6590d`.
The code pins the selected resource map and all baseline profile properties, and
checks all manifest native/lifecycle guards. The only per-JVM property delta is
`propertySurfaceNoAlloc=false` versus `propertySurfaceNoAlloc=true`. The same 888
official resources are used for both. The selected resource mapping digest in the
result uses SHA-256 of Python `json.dumps(map, sort_keys=True).encode()`.

Any proposed deployment must retain the complete selected resource mapping,
native/lifecycle guards and all other 769 baseline properties, changing only
`propertySurfaceNoAlloc` to `true`. No new class, native fallback, compiler mode,
compatibility flag or broader optimizer profile change is part of this candidate.
The existence of a microbenchmark benefit is not evidence of reduced gameplay
hitches; route-level allocation/call counts and frame timing remain separate gates.
