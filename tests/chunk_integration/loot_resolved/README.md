# Native resolved-loot calculation experiment

This B42.21 research prototype changes no shipped runtime code and installs
nothing into the game. No cache, deferred loot or classifier replacement is used.

The two native inner roll loops already resolve the candidate's original name.
The candidate saves that reference immediately after the lookup, before an
`Empty` fallback can overwrite it. When the original reference is nonnull,
cloned chance/modifier/base calculations reuse it for three later original-name
resolutions. A null original delegates to unchanged native chance, including
modifier-only and FluidContainer `Empty` fallbacks. Classification, removal-list
checks, junk normalization, live options/tags, arithmetic, random draws and
creation/callback code remain native. Nothing survives an iteration or crosses
a callback.

The builder clones native bytecode and adds test methods at initial class
definition. This is not an after-load production transformer; a runtime hook
would require separate design and acceptance work.

## Run

Set `PZ_GAME` to the directory containing external `projectzomboid.jar` and
`ZombieBuddy.jar`, `JAVA_HOME` to JDK25, and `PZ_JAVA` to the game's bundled
Zulu25 Java binary. Set `PZ_LOOT_RESULTS` to a new directory outside the game:

```sh
python3 tests/chunk_integration/loot_resolved/run.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" --java "$PZ_JAVA" \
  --output "$PZ_LOOT_RESULTS"
```

The default runs semantics only. `--measure` reserves the common exclusive
resource slot, then runs five independent JVMs. **Every measured JVM contains
both native and candidate bridges**, with twelve alternating AB/BA pairs per
group. `--forks`, `--pairs` (even, at least two) and `--iterations` control the
replications and calculation count per half. No comparison pairs two different
JVMs. Do not overlap timing with builds, game clients or other timing work, and
do not bypass admission failures.

Each JVM uses explicit `-Xms256m -Xmx256m -XX:+UseZGC -Xbatch`. The receipt records
all exact flags/classpaths/main arguments, runtime binary digest/version, native
and source digests, patched-class bytes and compiled harness bytes. JVM option
injection through environment variables is rejected. The caller supplies the
bundled binary explicitly; recognizing the Zulu vendor alone does not establish
exact game-runtime identity. Each JVM retains unified GC/safepoint and JIT logs.
Allocations and GC remain part of the synthetic workload; GC events are not
rejected as a class. These measurements do not support FPS extrapolation.

## Paired calculation and inputs

The source-level measured unit is the initial native name resolution, one native
`Rand.Next(10000)` draw, and the complete chance calculation. Both direct-call
bridges coexist in the candidate overlay and share the same generated prefix.
This is not a claim that the JVM executes an exact lookup count: the native
bridge's initial lookup result is unused and C2 may optimize it. No artificial
barrier or per-call sink is added to force that lookup to survive.
One common Java loop method has two symmetric static-call branches, selected
once per half. There is no MethodHandle or polymorphic dispatch per iteration;
the runner verifies compiled `invokestatic` callsites and absence of MethodHandle
usage in the harness. Both branches, every input group, the actual timer wrapper,
RNG reset and timing APIs are warmed before any retained window. Short repeated
timer-wrapper warmup continues the existing RNG stream to avoid thousands of
expensive CA RNG reconstructions; long warmup and every retained half reset the
native seed. This policy is explicit in the receipt. Group position
rotates across pairs; AB/BA order also changes across pairs and JVMs.

Before each half, outside timing, the native CellularAutomatonRNG is restored to
the same seed. Each pair records wall time, current-thread CPU, allocated bytes,
consumed float-bit checksum and a following RNG draw. Checksums and following RNG
must match. This seed reset and its allocations are outside the measured unit;
any resulting GC activity during the next half remains measured and logged.

Five explicitly synthetic groups cover different questions:

| Group | Inputs | Purpose |
| --- | ---: | --- |
| varied-unqualified-base | 64 | Primary short-name path; varied live tags, categories, flags, item types, chances, density and junk |
| single-unqualified-base | 1 | Constant short-name control for input/JIT specialization |
| varied-fulltype | 64 | Same native items with registered qualified full types |
| lookup-stress | 64 | Artificial equal four-way qualified/short/alias/import lookup stress |
| missing-empty-control | 64 | Missing originals and `Empty` variants that delegate to unchanged native chance |

Every created script item has its normal fulltype entry. The primary short-name
lookup still bypasses that map through native `FindItem` behavior. The qualified
control uses the same items. Alias/import weighting is deliberately artificial.
These constructor-built inputs exercise predicates; their equal coverage is not
an observed item distribution or gameplay frequency. No game scripts or mod
pack are loaded. `GROUP` and `INPUT` receipts retain every input and native
classification, tag count, float bits and RNG parity. Larger tag sets and
category precedence remain live native operations, without tag caching.

All logged compilation events within a timed window, including a +/-1ms margin,
reject the result. No method-name filter is used. Primitive report buffers avoid
printing between halves/groups. A prewarmed, nonbusy `LockSupport.parkNanos` path
waits at least 20ms after the final window before any reporting; interruption
fails instead of spinning. `REPORT_GAP` verifies the final window and separation.
A subprocess timeout retains partial stdout and explicit timeout metadata.
The result retains individual halves/pairs, per-JVM median deltas, AB/BA deltas,
sign counts, complete windows and any rejected JIT events. A qualified result
only applies to this synthetic calculation unit and exact JVM setup.

## Guards and semantic limits

The exact native ItemPickerJava guard, two original captures/two loop callsites,
four cloned helpers and three removed original-name resolutions are checked.
Changed/already transformed input is rejected. The runner pins 42 native classes
covering resolver buckets/modules, Item/classifier types, sandbox/config options,
Rand and native CA RNG, plus fallback component types. These on-disk byte guards
do not prove compatibility with later Java agents or reflective runtime changes.

Native `Item`, `ScriptManager` and `SandboxOptions` are final. Between a found
original and chance, only native Rand updates RNG/id state. Inside the native
modifier/classifier/removal-list path there is no Lua callback, item creation or
script mutation before the base lookup removed by the prototype. The live tag
HashSet and current category/flags are evaluated every call. Unsynchronized
cross-thread script/tag mutation is outside this proof.

The original 190 semantic rows remain compared between stock/candidate overlays,
including raw float bits, live mutations/replacements, exceptional inputs and
both actual inner roll callsites without creation. All 257 additional input rows
also compare both direct bridges in the same JVM against native chance and RNG.
The no-creation loops include a valid FluidContainer `Empty` fallback. They do
not establish successful factory/configuration, normal item initialization,
nested callback order, actual reload, source-square regions, full-mod gameplay
or menu Host networking. Those remain separate gates before runtime adoption.
Mandatory GENERATOR/IS_MEMENTO tag probes remain native; aggregate classification
samples cannot predict this resolver candidate's frame-time impact.
