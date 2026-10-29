# BetterContainers permission calculation experiment

Research only. This runs the selected BetterContainers Lua in the game's real
Kahlua VM using JDK 25, without launching the game or installing a mod. External
Workshop/game files remain inputs. Generated output goes into a new directory.

The candidate saves the six normalized sandbox Booleans in invocation locals.
It still calls the original `getSandbox` for every computation, returns fresh
sandbox/effective/UI/gate tables, and calls all three translations in their
original order. If another mod replaces the public `getSandbox`, it delegates to
the original computation. It keeps no result or settings cache.

`candidate.py` accepts one exact selected `Permissions.lua` SHA-256. The runner
also pins the selected `Proximity.lua` and `Proximity_ISInventoryPage.lua`, copies
the inputs, and records fixture/native class/game JAR/stdlib/JDK identities.
It derives the sibling client source paths from the shared permissions path.

```sh
python3 tests/chunk_integration/container_permissions/run.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" \
  --permissions "$BC_LUA/shared/BetterContainers/Permissions.lua" \
  --output "$PZ_PERMISSIONS_RESULTS"
```

Add `--measure --iterations 10000` for five alternating stock/candidate JVM
pairs, six warmup loops and five measured rounds per workload. This acquires the
common exclusive admission slot and waits for other native/measurement work;
run the measurement outside the sandbox on macOS so admission probes work. The
workloads consume one fresh computation and four fresh computations per loop,
with alternating local corpse preferences. They report wall time, current-thread
CPU and allocations. The four-computation workload represents the upper normal
permission-read count in the highlighted inventory-page update, not its entire
UI update cost. It does not include native rendering or translation lookup:
`getTextOrNull` is a Lua callback returning the translation key during timing.

Correctness executes 4096 Boolean policy/preference combinations, non-Boolean
normalization, nil translations, returned-table mutation, translator-triggered
settings changes and compute reentry, option `__index` callbacks, and replacement
of public `getSandbox`. It also executes the selected original inventory-page
update and unedited `DoAutoLock` function body with explicit world/UI doubles:
transfer, inventory and highlight Lua callbacks mutate settings between its four
permission reads. The test requires all four reads and twelve translation calls
and compares their results and callback order. This establishes those local Lua
semantics; it does not establish full-pack or Host integration.

An invocation-wide permission cache is unsafe: `DoAutoLock` calls transfer and
container methods; the highlight admission helper calls `inventory:getType`;
clearing old highlights calls parent methods before the corpse-only read.
These callbacks may change settings or reenter Lua. Public callers can also
mutate returned tables. Dropping later computations would additionally drop
translation callback effects. The candidate preserves these boundaries.

The result is a microbenchmark of a small permission calculation. No FPS or
frame-time improvement follows from it. Any delivery would require an explicit
integration into a maintained upstream/fork source, compatibility checks for
that exact load order, and the selected full-pack SP/Host scenario. This fixture
is not a runtime compatibility wrapper and does not ship in either mod.

## Observed budget

The 2026-10-29 macOS/JDK 25.0.1 run used five alternating pairs, 10,000
iterations, and the pinned selected sources. All semantic checks and consumed
checksums matched. Median wall time was 3.464 us stock / 2.876 us candidate for
one computation, and 13.592 us / 11.565 us for the four-consumer loop. The median
paired saving was 0.560 us and 2.131 us respectively; every pair saved CPU time.
The four-consumer wall saving ranged from 1.850 to 2.196 us across pairs.
Allocation remained approximately 2,420 bytes per single-computation loop and
9,623 bytes per four-consumer loop, with zero paired difference. These figures
include fixture loop/call overhead. Warmup and `-Xbatch` were used; this runner
does not independently audit JIT-compilation overlap.

The small CPU improvement is reproducible for these inputs, but approximately
0.0021 ms per four-read update does not establish a useful driving-stutter fix.
The candidate retains the existing allocation pressure and translation work.
Keep it as a tested upstream/source-level possibility; prioritize a larger
measured mechanism before paying for runtime integration and full-pack checks.

Paired candidate savings (stock minus candidate; median round per JVM):

| Pair | Single wall, us | Single CPU, us | Four-consumer wall, us | Four-consumer CPU, us | Allocation difference |
|---|---:|---:|---:|---:|---:|
| 1 | 0.560 | 0.556 | 2.131 | 2.081 | 0 B |
| 2 | 0.426 | 0.523 | 2.123 | 2.120 | 0 B |
| 3 | 0.583 | 0.583 | 2.171 | 2.163 | 0 B |
| 4 | 0.652 | 0.642 | 2.196 | 2.202 | 0 B |
| 5 | 0.546 | 0.546 | 1.850 | 1.810 | 0 B |

Selected Lua input pins (SHA-256):

- `Permissions.lua`: `27def55fa7ed50eda0554f0c5d248ee37352066f663f3e1c16cfed529e97b409`
- `Proximity.lua`: `cc4838096861abdf9051dbb666c5155932756c4923532554255c08389ab0074f`
- `Proximity_ISInventoryPage.lua`: `c04e7bb999deb12f74dcbe35b78e5c02d10fb0adeaaac41b81ad4ca36908d0dd`
