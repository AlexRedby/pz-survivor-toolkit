# Fog object-prefix operation candidate

Development-only B42.21 experiment. It creates two standalone scanners from the exact
15-instruction object-prefix search in `FBORenderCell.renderFog`. The candidate repeats
that prefix four times before the loop backedge. This removes three loop backedges
per four non-matching objects. It keeps each size check, array access, virtual
`getRenderInfo(player)` call, lazy initialization, layer read, first-MinusFloor exit,
and exception order. There is no object cache or traversal removal.

The generator verifies pinned native class resources and the exact instruction
sequence. It separately extracts the original official-overlay search and requires
byte-identical generated scanners. It never transforms `FBORenderCell` or changes
any game installation, optimizer profile, or production patch.

The scanner returns the matching index; the surrounding profiler scope and
`ImprovedFog.renderRowsBehind` call are outside this experiment. Their order and
iterator behavior must remain unchanged in any eventual runtime candidate. Passing
this harness does not validate the complete fog method, rendered rectangles, SP,
Host, or a gameplay performance improvement.

```sh
python3 tests/chunk_integration/fog_operation/run.py \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --official-overlay "$PZ_OFFICIAL_CLASSES" \
  --output "$CHECK_OUTPUT"
```

Inputs are the game Java directory, JDK 25+, and the original pinned official class
ZIP. Output must be a new directory outside the installation. Both Java helpers use
`--release` with `JavaPatches/build.py`'s `JVM_TARGET` (25); the generated scanner
uses class-file major 69. The runner validates the selected JDK and scanner major. Checks use real game
`IsoObject.getRenderInfo` and `ObjectRenderInfo`, plus virtual-call probes for ordered
access, an identical thrown sentinel, and array mutation. Cases include all player
indices, empty and short prefixes, every first-hit position through 32 objects,
misses, null objects/arrays, invalid sizes, and invalid player indices. Object-state
snapshots include lazy creation, layers, target alpha, and duplicate identities.

Add `--measure` for a bounded five-fork CPU diagnostic with exclusive resource
admission, 256 MiB heap, explicit warmup, paired alternating modes, seven rounds,
and retained JIT/GC logs. The fixtures include empty, first-hit, mixed short,
short-miss, late-hit, dense-miss and long-miss arrays. The generator's scanner
methods are not inlined into the synthetic driver, to keep separate compilation
boundaries visible. CPU time is measured on the benchmark thread. Arrays are
synthetic and cache-resident; there is no claim that they match the game's prefix
length distribution or memory locality. Relevant compilation overlapping a timed
window rejects timing qualification. Measurement requires an available, enabled
current-thread CPU timer; nonpositive operation counts or wall/CPU durations reject
the run. The correctness command also checks rejection with the CPU timer disabled. A clean timing gate alone does not establish
usefulness; short-path regressions and unstable or negligible gains reject adoption.

The candidate is rejected. No runtime integration, machine-code follow-up, or
further adoption work is queued. `fogPass=false` remains.

## Outcome

The retained timing series ran on macOS with JDK 25 using the earlier scanner
helper emitted at class-file major 61 (Java 17); its Java harness was compiled
with that JDK's default target. All 2419 correctness vectors passed. Five warmed
forks retained 490 timed windows with identical fixture checksums and no relevant JIT
compilation overlap. Both scanners and the real getter reached C2 before timing.
The median paired CPU changes were: first hit +9.31%, short miss +5.36%, long miss
+1.16%, dense miss -0.02%, late hit -8.22%, and mixed short prefixes -8.32%.
The first-hit regression appeared in all five forks. The candidate therefore fails
the usefulness gate and remains test-only. These are synthetic per-scan timings;
no frame-time gain was established. Whether C2 already partially unrolls the stock
loop was not established by inspecting generated machine code. That further gate
is unnecessary for this rejected candidate.

After correcting the helpers to the project JVM target 25, a fresh correctness-only
run passed all 2419 vectors with scanner major 69. The generated scanner differs
from the earlier measured scanner only in its class-file version; its instruction
bytes are unchanged. The timing series was not rerun and remains attributed to
the earlier helper. The candidate stays rejected.
