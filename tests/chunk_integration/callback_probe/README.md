# Native LoadGridsquare callback census

This is a test-only fixture for B42.21 and ZombieBuddy 2.3.4+. It observes the
original `Event.trigger` and `LuaCaller.protectedCallVoid` methods with advice;
it never replaces a callback or changes their return/error behavior. It measures
only direct Lua handlers of `LoadGridsquare`: calls, inclusive nanoseconds and
maximum duration per closure identity and thread. File/line rows can repeat across
closures or threads. Inclusive nested rows must not be summed as exclusive CPU
time. Indirect LuaCaller calls inside a handler
are excluded. Nested events have separate frames; nested LoadGridsquare handlers
are measured individually, and their time remains included in the outer handler.
Durations are unadjusted and include instrumentation overhead.

Build into a new standalone output directory, using an already owned disposable
cache containing a nonempty regular `smoke-user.txt` marker:

```sh
python3 tests/chunk_integration/callback_probe/build.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" \
  --output "$PZ_PROBE_OUTPUT" --cache "$PZ_TEST_CACHE" --check
```

The builder consumes local native JARs and produces
`$PZ_PROBE_OUTPUT/PZChunkCallbackProbe`. It does not install files into the game,
copy game/upstream runtime classes, fetch dependencies, or change the optimizer
profile. `--check` runs a headless JVM with real ZombieBuddy weaving and native
Kahlua; it does not launch the game or benchmark CPU performance. The source
snapshot hashes and native guards are recorded in `build-receipt.json` and the
fixture JAR. The fixture-specific token is also written to
`$PZ_TEST_CACHE/chunk-callback-probe.opt-in`; an existing token is refused so an
active probe's authorization cannot be replaced by a rebuild.

Add `PZChunkCallbackProbe` to the explicit startup test Mod ID list and pass:

```sh
--mod-source "PZChunkCallbackProbe=$PZ_PROBE_OUTPUT/PZChunkCallbackProbe"
```

Use the existing [startup runner](../../native_queue/README.md) with its normal
desktop/owned-cache policy. Keep the token in the actual client cache selected
for that run; if preparation recreates the cache, copy this fixture's token there
only after verifying the new cache is owned. The token and owned marker must be
present before the Java entry point runs. Different clients need their own
explicitly authorized cache marker; never place the token in an ordinary profile.
The default Lua fixture finishes at `OnGameStart`, so this measures startup loading
and produces `chunk-callbacks.tsv` plus `chunk-callbacks-status.txt` in the owned
cache. Require `status=complete` before interpreting the aggregates. Removing the
fixture from the selected test Mod IDs ends its use; nothing is installed globally.

There is no probe output during capture. Telemetry is bounded to 16 threads,
128 handlers per thread and 64 nested event frames. Capacity, nesting or telemetry
failures disable measurements and retain a diagnostic. Original callbacks still
run. On finish, partial telemetry is explicitly marked `status=incomplete` with
the reason. Missing/foreign cache authorization produces no measurements.

Before enabling, both builder and runtime check these exact native class bytes:

| Resource | SHA-256 |
| --- | --- |
| `zombie/Lua/Event.class` | `cf4b0ba953b8f965fbcacb73ebb5d1a173dc3ed140656e15b90ad932eff0e952` |
| `se/krka/kahlua/integration/LuaCaller.class` | `0443930027e8f312ae9cb192c628f4b6c10743204597c508f8693cfd7bd79d0b` |

These resource guards do not establish compatibility with other in-memory
weaving. The checks exercise actual woven Event returns, callback side effects,
both three-argument LuaCaller overloads, direct/indirect/nested calls, escaping
error identity, cache guards, quiet capture, capacity failure and continued native
callback execution. They do not establish full-pack or Host compatibility.

The earlier disposable prototype was used for the separate full-pack startup
profile. That result is not a native run of this final fixture and its guards.
This fixture provides no moving-route coverage, frame attribution, exclusive
timing, or evidence that a measured callback caused a frame hitch.
