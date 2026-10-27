# IsoLot lock experiment

Development-only candidate for the observed `IsoLot.get` contention between animal-zone
generation on MainThread and World Streamer. No production mod, optimizer manifest or
installed game consumes these files.

Both native `get` overloads synchronize on `IsoLot.class` across pool allocation and the
entire file read/parser. Native `ObjectPool.alloc` and `release` already synchronize on
the pool. Each borrowed lot has its own file, buffer, offsets and payload. The candidate
removes only `ACC_SYNCHRONIZED` from both `get` methods; native `put`, pool locking,
file reads, error handling and every instruction remain unchanged. Removing only one
overload would leave the other holding the class monitor through the same I/O.

The exact native class and pool hashes are admission guards. The runner also rejects
any candidate whose complete class-file diff is more than two cleared access bits.
Normal world startup finishes metadata loading before starting World Streamer. Normal
teardown stops and joins the streamer before `IsoLot.Dispose`; the latter was already
unsynchronized and does not include borrowed objects in its pool iteration. This
candidate does not make concurrent teardown or arbitrary direct pool misuse safe.

## Run

Supply an external B42.21 game directory containing `projectzomboid.jar` and
`ZombieBuddy.jar` (ASM dependency only), and a JDK 25 home containing `bin/java`.
Use a new output directory outside the installed game. No native game binary is copied
into the repository and no game or GUI is launched.

```sh
python3 tests/chunk_integration/lot_lock/run.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" --output "$PZ_LOT_RESULTS"

# Separate new directory for bounded performance evidence:
python3 tests/chunk_integration/lot_lock/run.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" --output "$PZ_LOT_TIMING" \
  --measure --forks 3 --iterations 20000 --resource-wait 60
```

On macOS, the measurement command needs unsandboxed host-resource inspection. Keep
the common exclusive admission gate and bounded wait. A busy slot leaves correctness
evidence and a blocked result without starting timed forks.

The result directory retains source snapshots, native/candidate hashes, byte-diff
offsets, JVM version, correctness logs, admission, JIT logs and individual timed rounds.
Changed or already transformed native input fails closed. Each JVM has an isolated
cache/home and runs in an empty scratch working directory.

## What the checks establish

The fixture writes its own valid legacy/version-1 lotpack files, then invokes actual
native `get`, `load`, `put` and `Dispose`. Eighteen identical stock/candidate vectors
cover RLE and explicit empty squares, multiple levels, offsets/data, cell coordinates,
both overloads, header identity, pooled file reuse/change/close/reopen and four
concurrent borrowers retaining distinct identities for 24 rounds. Dispose coverage
checks pooled stream lifetime; full world metadata teardown is a separate gate.

A latch blocks one real native parser inside an injected `RandomAccessFile.read`.
The stock control must block the second caller on `IsoLot.class` with the first caller
as owner. The candidate must finish the second parse with a different lot while the
first read remains blocked. Both parsed results must still match. This demonstrates
lock scope deterministically; the injected wait is not a measured disk latency.

Optional timing uses real native file I/O over small synthetic, warm files with one
and two reader threads. It alternates stock/candidate fork order, consumes equal output
checksums, retains all rounds and paired medians, and rejects relevant JIT compilation
inside timed windows. The per-operation time is whole-workload wall time divided by
completed operations, not individual read latency. Pool reuse/file reopening remains
native and can differ with scheduling. Timing qualification means these measurement
gates passed; it is not runtime/gameplay qualification or a minimum speedup guarantee.

## Scope and next gate

The pinned optimizer keeps native IsoLot/ObjectPool/ZoneGenerator. SP tree counting
composes authored level-zero tiles with map priority, then influences the list from
which RNG selects animal path extensions. The candidate leaves that list, RNG calls,
generation thread, zone registration, migration and client/server branch unchanged.
Server extensions follow their existing separate random selection path.

This change cannot remove MainThread's own slow lotpack reads. Thresholded JFR reads
report elapsed calls without offsets; repeated filenames do not establish identical
chunk/byte reads or a disk/WPR cause. No cache, worker world generation, file preloading
or buffer-size change is introduced.

Before runtime delivery, verify the final patch-loading mechanism and pinned optimizer
combination with the full selected pack in isolated SP/menu Host, including streaming,
animal-zone geometry/RNG/persistence, map transitions and shutdown/reload. Compare
actual frame and I/O evidence before claiming a driving improvement. The existing
capture supplies the lead; no new user capture is required for these local gates.
