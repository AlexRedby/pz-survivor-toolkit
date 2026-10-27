# IsoLot single-reader follow-up

Development diagnostic for the original experiment's final paired fork: single-reader
wall-time medians regressed by 30.22%, while the first two pairs differed by +0.03%
and +0.78%. The retained original data has no worker CPU, allocation or real-I/O counts,
so that outlier alone cannot distinguish repeatable code cost from scheduling/I/O effects.
The old sources under `../lot_lock` remain unchanged and are reused directly.

## Prepare and run

Use explicit external B42.21 game and JDK 25 homes and a fresh output directory.
Preparation compiles and generates overlays without running the native workload:

```sh
python3 tests/chunk_integration/lot_lock_followup/run.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" --output "$PZ_LOT_PREPARED"
```

Timed work requires the common exclusive admission slot. Do not run concurrently
with an admitted SP/Host renderer session. On macOS, run this command outside the
sandbox for normal host-resource inspection; preserve its admission and bounded wait:

```sh
python3 tests/chunk_integration/lot_lock_followup/run.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" --output "$PZ_LOT_FOLLOWUP" \
  --measure --forks 5 --iterations 100000 --rounds 5 --warmup 20 --resource-wait 60
```

Each paired JVM runs sequentially, alternating stock/candidate order between forks.
Default reservation: one 256 MiB Java heap, 256 MiB native estimate, two CPUs and an
exclusive slot. Admission applies the common disk reserves too. Each subprocess has
a 180-second deadline; waits are bounded at 0..900 seconds; the runner bounds all
iteration/fork/round parameters. Partial logs, commands and rows survive failure.
No GUI, installed game write or native world launch occurs.

## Workloads and measurements

Both modes execute actual native `IsoLot.get`, its native parser, native buffered I/O,
`put` and synchronized ObjectPool. The candidate is the original guarded two-bit
`ACC_SYNCHRONIZED` removal. The original synthetic fixtures and expected arrays are
reused reflectively, validated with the original checks, then consumed through direct
native calls. Both primitive and boxed overloads alternate, and every payload integer
contributes to the original checksum workload.

- `fixed-single` uses one native pooled object/file path after priming. It retains
  zero-open and identical refill/byte-count gates across all measured rounds/modes.
- `mixed-single` followed by `mixed-two` reproduces the old alternating phases:
  worker zero reads the legacy fixture and worker one reads version 1. Both share the
  native pool, so two-worker scheduling may change reopening frequency. The workload
  and checksum match; equal real-I/O work is deliberately not assumed here.

Before each case, the native pool is cleared. A 20,000-operation cross-path prime
precedes the cases, then twenty warmup rounds precede measurements. Eight rounds left
one native buffered-reader `seek` compilation inside an observed mixed-two window;
that attempt remains unqualified. The zero-overlap gate is unchanged. Every round retains
coordinator wall time, each worker's own loop wall/thread CPU/allocated bytes, actual
successful buffered-reader opens, completed buffer refills and returned read bytes.
The coordinator's wall time includes latch release, worker completion and joins; worker
CPU/allocation snapshots surround the native loop. Expected checksum calculation and
thread creation happen before the timed window. Per-phase checksums must match.

The identical telemetry overlay in both modes adds a thread-local increment after
each completed native buffered-reader constructor, and before `fillBuffer` returns.
The native buffer/parser instructions and real RandomAccessFile calls remain present;
no reader/parser implementation is copied or substituted. `opens` counts successful
BufferedRandomAccessFile construction, not OS close operations. `refills` includes
zero-byte/EOF returns; `read_bytes` sums nonnegative actual returned bytes, with EOF
counted separately. Native class hashes and overlay/source hashes are retained.

JIT and GC/safepoint logs cover every fork. Relevant compilation inside a timed phase
rejects timing qualification, and every raw row remains available. The summary reports
per-fork medians and paired percentage deltas for wall, CPU, allocation and I/O metrics.

## Interpretation limits

This is a counter-instrumented synthetic warm-file diagnostic. Counters add overhead
and can change absolute cost/JIT shape; they are equal in both modes, but the result
does not quantify uninstrumented gameplay throughput. Stable fixed-path CPU differences
across forks support a repeatable code-cost lead. Wall divergence without a matching
CPU increase is compatible with off-CPU delay; additional evidence is needed to assign
its cause. Changed opens/refills/bytes in mixed phases demonstrate changed I/O workload
and preclude treating that phase as equal-I/O parser throughput.

Returned I/O bytes count logical native read results, not physical disk traffic or OS
cache misses. The runner neither flushes caches nor diagnoses storage/WPR latency.
It does not establish driving/frame-time benefit, full-pack behavior or lifecycle safety;
the existing native SP/menu-Host qualification gates still apply.
