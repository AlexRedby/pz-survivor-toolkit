# Cutaway operation arithmetic experiment

Test-only B42.21 experiment for `ChunkLevelData.calculateOccludingSquares` and
`shouldRenderSquare`. The generator copies both complete method bodies directly
from pinned native classes and, separately, the original official optimizer ZIP.
It turns each original receiver into the first argument of a standalone static
method and redirects only the internal helper call to its extracted counterpart.
Native and official extractions remain distinct: the official recompilation has
branch and compound-assignment bytecode differences.

The candidate replaces only the mask-coordinate sequence after the native output
height write. For the fixed loop index `0 <= i < 64`,
`i % 8 + (i / 8) * 8` equals `i`. Thus `1 << i` preserves the native **int** shift,
including masking shift distances by 31 and sign extension to long at bit 31.
The experiment deliberately preserves the existing masks; changing them to a
64-bit shift is a separate behavioral question.

No square-array index is substituted for the live flag index. A direct flag lookup
would need to prove the mutable square's chunk, coordinates and level correspond
to that index. Such a guard retains the original coordinate work and adds checks;
no cheaper guarded path was identified. The candidate keeps every native field
read, flag-array access, exception boundary and virtual `getSquaresForLevel`,
`getVisionMatrix`, and `getGridSquare` call. It creates no persistent cache.

```sh
python3 tests/chunk_integration/cutaway_operation/run.py \
  --game "$PZ_GAME" --jdk "$PZ_JDK" \
  --official-overlay "$PZ_OFFICIAL_CLASSES" --output "$CHECK_OUTPUT"
```

The output must be a new directory outside the game installation. Helpers and
generated classes use the shared `JavaPatches/build.py` JVM target, currently 25.
The command checks 1,827 vectors against the actual native operation, comparing
return/exception class, all player masks and every height-array element. The four
extracted paths are native stock/candidate and original-official stock/candidate.
Cases include normal, short, empty/all-null, sparse and unusual input shapes;
clipping and integer overflow; invalid players and null/ragged arrays; foreign or
null chunk and changed coordinates/level; vision and below-square branches; all 64
single-square masks; and state changed between repeated invocations. Game objects
are allocated without constructors through test-only Unsafe, avoiding world setup.
These fixtures exercise real native accessors, with no callback replacement.

Add `--measure` for three sequential JVM forks under the common exclusive resource
admission (256 MiB heap, 256 MiB native estimate, two CPUs). The CPU diagnostic
alternates stock/reduced original-official operations in seven rounds after shared
warmup over six cache-resident shapes: empty, sparse, normal, vision, below-square,
and unusual/null-chunk. Each window contains 200,000 complete operations. Native
short arrays are correctness-only because the operation necessarily throws on the
missing slot. Both methods must reach C2 before timing; any relevant compilation
or deoptimization overlapping a measured window disqualifies timing. Disabled or
unavailable CPU timers and nonpositive operations/wall/CPU times are rejected.

The helper stays inlineable, matching the recorded native JFR evidence that it was
already inlined. Only complete extracted operations are excluded from driver
inlining. No runtime class is transformed, game launched, profile changed, mod
installed, or gameplay/FPS claim made. Synthetic CPU evidence can reject this
candidate; it cannot by itself qualify a runtime patch.

## Outcome

The mask simplification is rejected for runtime adoption. The final macOS/JDK 25
series passed 1,827 correctness vectors and retained 252 timed windows over three
JVMs. Both official full operations reached C2 before timing; relevant JIT overlap
was zero and fixture checksums matched across modes and forks.

Median of the three per-fork paired CPU changes (negative is faster):

| Shape | Candidate CPU change |
| --- | ---: |
| Empty/all-null | -0.24% |
| Sparse | -2.57% |
| Normal | -0.55% |
| Vision bit set | +0.05% |
| Some below squares present | -0.11% |
| Some null square chunks | -0.57% |

Normal per-fork changes were -4.58%, -0.55% and -0.54%; the first fork also had
+4.98% below-square and +4.65% vision regressions. The smaller stable changes are
roughly one or two nanoseconds per complete synthetic operation, with no useful
common reduction established. The timing gate verifies execution stability, not
usefulness. The exact C2 instruction transformation was not inspected.

This splice does not remove the live flag-index calculation identified by the
recorded `shouldRenderSquare` leaf samples. It cannot establish savings for that
leaf or measurable frame-time improvement. No runtime/profile change or gameplay
qualification is proposed from this experiment.

An earlier exploratory timing series used the exact official operation but called
the native helper directly, with shorter windows. It is an obsolete-boundary
series, excluded from the final table and acceptance evidence. The final series
above uses both the exact official operation and its exact extracted helper.
