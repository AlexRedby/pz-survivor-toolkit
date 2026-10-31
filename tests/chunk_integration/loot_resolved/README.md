# Native resolved-loot calculation experiment

Research-only B42.21 prototype. It changes no shipped runtime code and installs
nothing into the game. No cache, deferred loot or classifier replacement is used.

The two native inner roll loops already resolve the candidate's original name.
The candidate saves that reference immediately after the lookup, before an
`Empty` fallback can overwrite it. When that original reference is nonnull, a
cloned chance calculation reuses it for three later original-name resolutions:
`getActualSpawnChance`, `getLootModifier(String)`, and `getBaseChance`. A null
original delegates to the unchanged native chance method, including successful
modifier-only and FluidContainer `Empty` fallbacks.

The builder clones native chance, both modifier overloads and base-chance
bytecode, inserting a resolved parameter and changing only the initial lookup
and helper callsites. The classifier, removal list, junk normalization, sandbox
options, float arithmetic, random draws and all creation/callback code remain
native. The first outer resolution remains once per candidate. Nothing survives
an iteration or crosses a callback. This is broader than the earlier single
base-lookup experiment, and its benefit still requires measurement.

## Run

Set `PZ_GAME` to the directory containing the external `projectzomboid.jar` and
`ZombieBuddy.jar`, `JAVA_HOME` to JDK25, and `PZ_JAVA` to the game's bundled Zulu25
Java binary. Set `PZ_LOOT_RESULTS` to a new disposable directory outside the game:

```sh
python3 tests/chunk_integration/loot_resolved/run.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" --java "$PZ_JAVA" \
  --output "$PZ_LOOT_RESULTS"
```

The default performs semantics only. `--measure` additionally reserves the common
exclusive resource slot and compares five alternating stock/candidate JVM pairs.
Do not run timing alongside builds, game clients or other timing work. Admission
failure must not be bypassed. Timing requires the supplied runtime to identify
itself as Zulu; that vendor check does not establish exact game-runtime identity.
The caller supplies the bundled binary explicitly; the receipt records its byte
digest and complete version. Compile with JDK25.

Both modes use the same added calculation bridge and MethodHandle invocation.
One measured unit is the first original-name resolution, one native
`Rand.Next(10000)` draw, and the complete chance calculation. It is not the
entire native roll loop or a spawned-item benchmark. Four groups exercise
fulltype, module, alias and import lookup. Wall/CPU/allocation data, paired forks,
consumed checksums and JIT-overlap checks are retained. Every logged compilation
event in a timed window, including a +/-1ms boundary margin, rejects that timing
run as unqualified; the matching lines remain in the result. Timing APIs are
prewarmed, and primitive report buffers are printed only after all timed groups.
A prewarmed `LockSupport.parkNanos` path then waits at least 20ms before printing;
spurious wakeups re-park for the remaining duration, while interruption fails
the run. A `REPORT_GAP` receipt verifies separation from the last timing window.
The all-event JIT gate and its +/-1ms margin remain unchanged.

## Guards and semantic scope

The builder admits one exact native ItemPickerJava digest, checks two saved
originals/two changed loop calls/four cloned helpers/three removed initial
resolutions, and rejects modified/already transformed input. The runner pins
resolver/bucket/module, Item/classifier tag types, sandbox/config option classes,
Rand/RandAbstract/RandStandard, native CellularAutomatonRNG and fallback component
classes. These are on-disk native-byte guards, not proof against later Java
agents or arbitrary reflective changes to runtime objects.

`Item`, `ScriptManager`, and `SandboxOptions` are native final classes. Between
a found original and the chance call, only native Rand changes RNG/id state.
Inside native modifier/classification/removal-list helpers there is no Lua,
item creation or script mutation before the base lookup being removed. Item's
live HashSet tag membership and live category/flags remain evaluated each call.
Rand delegates to its native CA RNG, without script callbacks. The semantic
fixture seeds that same CA RNG deterministically, rather than replacing it with
`java.util.Random`. Unsynchronized cross-thread tag/script mutation and Java
transformations of skipped public helpers are outside this proof.

The harness compares raw float bits directly with native chance in each JVM,
then compares complete output streams between overlays. Cases include
qualified/unqualified/module/alias/import lookup, missing and Empty names, junk,
removal lists, float edges, changing tags/categories/flags/options, item
replacement and native RNG progression. It additionally enters both real native
inner roll methods for failed rolls and successful admission attempts rejected
as obsolete/missing, including a real FluidContainer script-component fallback.
These loop checks exercise the changed callsites and original-reference capture.
They deliberately create no loot and do not exercise item factory/configuration,
nested callbacks, actual script reload, source-square region variants, a full mod
pack, gameplay, or menu Host networking. Those remain separate delivery gates.

The experiment does not prove a driving-frame improvement. In particular,
mandatory GENERATOR/IS_MEMENTO tag probes remain native; resolver savings cannot
be inferred from aggregate JFR classification samples.
